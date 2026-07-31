'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'
import { tasks } from '@trigger.dev/sdk/v3'
import { placeDocument } from './chaining'
import type { AIDocumentResult } from '@/lib/ai/vertex'
import { generateDefaultMatterTitle } from '@/lib/utils/matterNaming'

// ── Read Staged Documents ─────────────────────────────────────────

export async function getStagedDocuments() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data } = await supabase
    .from('staged_documents')
    .select(`
      *,
      suggested_client:clients(id, name, gstin),
      suggested_matter:matters(id, title, financial_year, matter_code)
    `)
    .eq('org_id', orgId)
    .neq('status', 'assigned')
    .order('created_at', { ascending: true })

  return data ?? []
}

export async function getStagedDocumentCount() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return 0

  const { count } = await supabase
    .from('staged_documents')
    .select('id', { count: 'exact', head: true })
    .eq('org_id', orgId)
    .neq('status', 'assigned')

  return count ?? 0
}

// ── Upload to Staged (global upload) ─────────────────────────────

export async function uploadToInbox(formData: FormData) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const file = formData.get('file') as File
  if (!file) return { error: 'No file provided.' }

  const matterId = formData.get('matterId') as string | null

  const allowedTypes = ['application/pdf']
  if (!allowedTypes.includes(file.type)) {
    return { error: 'Only PDF files are supported.' }
  }

  const maxSize = 50 * 1024 * 1024 // 50MB
  if (file.size > maxSize) {
    return { error: 'File must be under 50MB.' }
  }

  // Path must be `staged/orgId/fileName` to match storage RLS policy
  const fileName = `staged/${orgId}/${Date.now()}_${file.name.replace(/\s/g, '_')}`

  const { error: uploadError } = await supabase.storage
    .from('staging')
    .upload(fileName, file, { contentType: file.type })

  if (uploadError) {
    console.error('Storage upload error:', uploadError)
    return { error: uploadError.message }
  }

  const { data, error } = await supabase
    .from('staged_documents')
    .insert({
      org_id: orgId,
      uploaded_by: user.id,
      storage_path: fileName,
      status: 'pending_assignment',
      suggested_matter_id: matterId || null,
      suggestion_reason: matterId ? 'Context-aware upload' : null,
    })
    .select('id')
    .single()

  if (error || !data) {
    console.error('Staged document insert error:', error)
    return { error: error?.message ?? 'Failed to stage document.' }
  }

  try {
    await tasks.trigger('analyze-staged-document', {
      stagedDocId: data.id,
      orgId: orgId,
      uploadedBy: user.id,
      storagePath: fileName,
    })
  } catch (err) {
    console.error('Failed to trigger analysis task:', err)
    // We still return success since the document was uploaded, 
    // but the user might need to retry analysis or do it manually.
  }

  revalidatePath('/inbox')
  revalidatePath('/', 'layout')
  return { success: true, id: data.id }
}

// ── Assign Staged Document to a Matter ───────────────────────────

export async function assignStagedDocument(
  stagedId: string,
  matterId: string,
) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  // Verify staged document belongs to this org
  const { data: staged } = await supabase
    .from('staged_documents')
    .select('id, storage_path, status, raw_metadata')
    .eq('id', stagedId)
    .eq('org_id', orgId)
    .single()

  if (!staged) return { error: 'Staged document not found.' }
  if (staged.status === 'assigned') return { error: 'Document already assigned.' }

  // Verify matter belongs to this org
  const { data: matter } = await supabase
    .from('matters')
    .select('id, org_id')
    .eq('id', matterId)
    .eq('org_id', orgId)
    .single()

  if (!matter) return { error: 'Matter not found.' }

  // 1. Copy file from 'staging' bucket to 'documents' bucket
  const baseName = staged.storage_path.split('/').pop() || 'document.pdf'
  const newPath = `${orgId}/${matterId}/${Date.now()}_${baseName}`

  const { data: fileData, error: downloadError } = await supabase.storage
    .from('staging')
    .download(staged.storage_path)

  if (downloadError || !fileData) {
    console.error('Failed to download from staging:', downloadError)
    return { error: 'Failed to access document file in staging storage.' }
  }

  const { error: uploadError } = await supabase.storage
    .from('documents')
    .upload(newPath, fileData, { contentType: 'application/pdf' })

  if (uploadError) {
    console.error('Failed to upload to documents bucket:', uploadError)
    return { error: 'Failed to copy document to matter storage.' }
  }

  let documentClass = 'proceeding'
  let documentCategory = null
  if (staged.raw_metadata) {
    const aiResult = staged.raw_metadata as unknown as AIDocumentResult;
    documentClass = aiResult.document_class || 'proceeding'
    documentCategory = aiResult.document_category || null
  }

  // 2. Create the documents record (source='inbox' → skips routing check)
  const { data: doc, error: docError } = await supabase
    .from('documents')
    .insert({
      matter_id: matterId,
      org_id: orgId,
      storage_path: newPath, // Correct path in documents bucket
      status: 'processing',
      source: 'inbox',
      created_by: user.id,
      document_class: documentClass,
      document_category: documentCategory,
    })
    .select('id')
    .single()

  if (docError || !doc) {
    console.error('Document insert error:', docError)
    // Clean up uploaded file if DB insert fails
    await supabase.storage.from('documents').remove([newPath])
    return { error: docError?.message ?? 'Failed to create document record.' }
  }

  // 2.5 Place document in graph
  if (staged.raw_metadata) {
    const aiResult = staged.raw_metadata as unknown as AIDocumentResult;
    // ensure chaining_attributes exists for placeDocument
    if (!aiResult.chaining_attributes) {
      aiResult.chaining_attributes = {} as any;
    }
    try {
      await placeDocument(supabase, doc.id, matterId, orgId, user.id, aiResult);
    } catch (e) {
      console.error('Failed to link document in graph:', e);
    }
  }


  // 3. Delete from staging bucket and mark staged as assigned
  await supabase.storage.from('staging').remove([staged.storage_path])

  await supabase
    .from('staged_documents')
    .update({ status: 'assigned' })
    .eq('id', stagedId)

  // 4. Trigger process-document job via Trigger.dev
  try {
    await tasks.trigger('process-document', {
      docId: doc.id,
      matterId: matterId,
      orgId: orgId,
      storagePath: newPath, // Match documents bucket path!
      uploadedBy: user.id,
    })
  } catch (err) {
    console.error('Failed to trigger process-document task:', err)
  }

  revalidatePath('/inbox')
  revalidatePath('/', 'layout')
  revalidatePath(`/matters/${matterId}`)
  return { success: true, documentId: doc.id }
}

// ── Auto-Create Client & Matter for Staged Document ──────────────────

export async function autoCreateClientAndMatterForStagedDocument(stagedId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  // 1. Fetch staged document
  const { data: staged } = await supabase
    .from('staged_documents')
    .select('*')
    .eq('id', stagedId)
    .eq('org_id', orgId)
    .single()

  if (!staged) return { error: 'Staged document not found.' }
  if (staged.status === 'assigned') return { error: 'Document already assigned.' }

  const metadata = staged.raw_metadata as any
  if (!metadata || !metadata.client_name) {
    return { error: 'Could not extract client details from document. Please assign manually.' }
  }

  // 2. Resolve Client (find by GSTIN or create new)
  let clientId: string
  let gstin: string | null = null
  if (metadata.gstin) {
    let s = metadata.gstin.trim().toUpperCase().replace(/[^A-Z0-9]/g, '')
    if (s.length === 15) {
      let state = s.substring(0, 2).replace(/O/g, '0')
      s = state + s.substring(2)
    }
    gstin = s
  }

  if (gstin) {
    const { data: existingClient } = await supabase
      .from('clients')
      .select('id')
      .eq('org_id', orgId)
      .eq('gstin', gstin)
      .is('deleted_at', null)
      .maybeSingle()

    if (existingClient) {
      clientId = existingClient.id
    } else {
      const { data: newClient, error: clientErr } = await supabase
        .from('clients')
        .insert({
          org_id: orgId,
          name: metadata.client_name,
          gstin: gstin,
          pan: gstin.substring(2, 12), // standard pan extraction from gstin
        })
        .select('id')
        .single()

      if (clientErr || !newClient) {
        return { error: clientErr?.message ?? 'Failed to auto-create client.' }
      }
      clientId = newClient.id
    }
  } else {
    // If no GSTIN, check by name
    const { data: existingClient } = await supabase
      .from('clients')
      .select('id')
      .eq('org_id', orgId)
      .ilike('name', `%${metadata.client_name}%`)
      .is('deleted_at', null)
      .maybeSingle()

    if (existingClient) {
      clientId = existingClient.id
    } else {
      const { data: newClient, error: clientErr } = await supabase
        .from('clients')
        .insert({
          org_id: orgId,
          name: metadata.client_name,
        })
        .select('id')
        .single()

      if (clientErr || !newClient) {
        return { error: clientErr?.message ?? 'Failed to auto-create client.' }
      }
      clientId = newClient.id
    }
  }

  // 3. Create Matter
  let clientName = metadata.client_name || 'Client'
  if (clientId) {
    const { data: clientObj } = await supabase.from('clients').select('name').eq('id', clientId).maybeSingle()
    if (clientObj?.name) clientName = clientObj.name
  }

  const financialYear = metadata.financial_year || '2023-24'
  const title = await generateDefaultMatterTitle(supabase, orgId, clientId, clientName, financialYear)
  const description = metadata.summary || null

  const { data: newMatter, error: matterErr } = await supabase
    .from('matters')
    .insert({
      org_id: orgId,
      client_id: clientId,
      title,
      financial_year: financialYear,
      description,
      status: 'active'
    })
    .select('id')
    .single()

  if (matterErr || !newMatter) {
    return { error: matterErr?.message ?? 'Failed to auto-create matter.' }
  }

  // 4. Assign the document to this new matter
  return assignStagedDocument(stagedId, newMatter.id)
}

// ── Discard Staged Document ───────────────────────────────────────

export async function deleteStagedDocument(stagedId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const db = createServiceClient()

  const { data: staged } = await db
    .from('staged_documents')
    .select('id, storage_path')
    .eq('id', stagedId)
    .eq('org_id', orgId)
    .single()

  if (!staged) return { error: 'Staged document not found.' }

  // Delete from storage
  await db.storage.from('staging').remove([staged.storage_path])

  // Delete record
  const { error } = await db
    .from('staged_documents')
    .delete()
    .eq('id', stagedId)

  if (error) {
    console.error('Discard staged error:', error)
    return { error: error.message }
  }

  revalidatePath('/inbox')
  revalidatePath('/', 'layout')
  return { success: true }
}

export const discardStagedDocument = deleteStagedDocument


// ── Re-evaluate Staged Documents ─────────────────────────────────────────

export async function reevaluateStagedDocuments() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return

  const { data: staged } = await supabase
    .from('staged_documents')
    .select('*')
    .eq('org_id', orgId)
    .eq('status', 'ready_to_assign')

  if (!staged || staged.length === 0) return

  let revalidated = false

  for (const doc of staged) {
    const metadata = doc.raw_metadata as any
    if (!metadata) continue

    let clientId: string | null = null
    let gstin: string | null = null

    if (metadata.gstin) {
      let s = metadata.gstin.trim().toUpperCase().replace(/[^A-Z0-9]/g, '')
      if (s.length === 15) {
        let state = s.substring(0, 2).replace(/O/g, '0')
        s = state + s.substring(2)
      }
      gstin = s
    }

    if (gstin) {
      const { data: existingClient } = await supabase
        .from('clients')
        .select('id')
        .eq('org_id', orgId)
        .eq('gstin', gstin)
        .is('deleted_at', null)
        .maybeSingle()
      if (existingClient) clientId = existingClient.id
    } else if (metadata.client_name) {
      const { data: existingClients } = await supabase
        .from('clients')
        .select('id')
        .eq('org_id', orgId)
        .ilike('name', `%${metadata.client_name}%`)
        .is('deleted_at', null)
        .limit(1)
        
      if (existingClients && existingClients.length > 0) {
        clientId = existingClients[0].id
      }
    }

    if (clientId) {
      const { data: matters } = await supabase
        .from('matters')
        .select('id')
        .eq('client_id', clientId)
        .eq('status', 'active')

      if (matters && matters.length > 0) {
        await supabase
          .from('staged_documents')
          .update({
            suggested_client_id: clientId,
            suggested_matter_id: matters[0].id,
            suggestion_reason: 'Match found in re-evaluation'
          })
          .eq('id', doc.id)
        revalidated = true
      }
    }
  }

  if (revalidated) {
    revalidatePath('/inbox')
    revalidatePath('/', 'layout')
  }
}
