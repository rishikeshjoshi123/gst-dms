'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'
import { after } from 'next/server'
import { tasks } from '@trigger.dev/sdk/v3'
import type { AIDocumentResult } from '@/lib/ai/vertex'


// ── Read Staged Documents ─────────────────────────────────────────

export async function getStagedDocuments() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data, error } = await supabase
    .from('staged_documents')
    .select(`
      *,
      suggested_client:clients(id, name, gstin),
      suggested_matter:matters!staged_documents_suggested_matter_id_fkey(id, title, financial_year, matter_code)
    `)
    .eq('org_id', orgId)
    .in('status', ['pending_assignment', 'analyzing', 'ready_to_assign', 'failed'])
    .order('created_at', { ascending: true })

  if (error) {
    console.error('Failed to load staged documents:', error)
    return []
  }

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
    .in('status', ['pending_assignment', 'analyzing', 'ready_to_assign', 'failed'])

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

  if (matterId) {
    const { data: matter } = await supabase
      .from('matters')
      .select('id')
      .eq('id', matterId)
      .eq('org_id', orgId)
      .is('deleted_at', null)
      .maybeSingle()
    if (!matter) return { error: 'The selected matter is not available.' }
  }

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
      intake_matter_id: matterId || null,
    })
    .select('id')
    .single()

  if (error || !data) {
    console.error('Staged document insert error:', error)
    return { error: error?.message ?? 'Failed to stage document.' }
  }

  // Trigger.dev accepts the work independently of the browser request. Do
  // this after the Server Action responds so a slow task gateway can never
  // leave the upload UI stuck on "Uploading…" after the file is stored.
  after(async () => {
    try {
      await tasks.trigger('analyze-staged-document', {
        stagedDocId: data.id,
        orgId,
        uploadedBy: user.id,
        storagePath: fileName,
      })
    } catch (err) {
      console.error('Failed to trigger analysis task:', err)
      const serviceClient = createServiceClient()
      await serviceClient
        .from('staged_documents')
        .update({ status: 'failed', suggestion_reason: 'Analysis could not be queued. Retry this document.' })
        .eq('id', data.id)
        .eq('org_id', orgId)
    }
  })

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
  if (staged.status === 'manually_assigned' || staged.status === 'auto_assigned') return { error: 'Document already assigned.' }

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

  const aiResult = staged.raw_metadata as unknown as AIDocumentResult | null
  const documentClass = aiResult?.document_class || 'proceeding'
  const documentCategory = aiResult?.document_category || null

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
      doc_type: aiResult?.doc_type || null,
      reference_number: aiResult?.reference_number || null,
      doc_date: aiResult?.doc_date || null,
      direction: aiResult?.direction || null,
      issued_by: aiResult?.issued_by || null,
      financial_year: aiResult?.financial_years?.[0] || null,
      summary: aiResult?.summary || null,
      raw_metadata: aiResult || {},
      ai_prompt_version: aiResult?.prompt_version || null,
    })
    .select('id')
    .single()

  if (docError || !doc) {
    console.error('Document insert error:', docError)
    // Clean up uploaded file if DB insert fails
    await supabase.storage.from('documents').remove([newPath])
    return { error: docError?.message ?? 'Failed to create document record.' }
  }

  // 3. The copied document is durable. Dispatch processing after the response
  // has been sent, so a slow task gateway cannot block the review UI.
  after(async () => {
    try {
      await tasks.trigger('process-document', {
        docId: doc.id,
        matterId,
        orgId,
        storagePath: newPath,
        uploadedBy: user.id,
      })
    } catch (err) {
      console.error('Failed to trigger process-document task:', err)
      const serviceClient = createServiceClient()
      await serviceClient
        .from('documents')
        .update({ status: 'failed', review_reason: 'Processing could not be queued. Retry this document.' })
        .eq('id', doc.id)
        .eq('org_id', orgId)
    }
  })

  // 4. The matter document is now the durable retry target, so clear staging.
  await supabase.storage.from('staging').remove([staged.storage_path])
  await supabase
    .from('staged_documents')
    .update({ status: 'manually_assigned' })
    .eq('id', stagedId)

  revalidatePath('/inbox')
  revalidatePath('/', 'layout')
  revalidatePath(`/matters/${matterId}`)
  return { success: true, documentId: doc.id }
}

// ── Auto-Create Client & Matter for Staged Document ──────────────────

export async function autoCreateClientAndMatterForStagedDocument(stagedId: string, selectedFy?: string) {
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
  if (staged.status === 'manually_assigned' || staged.status === 'auto_assigned')
    return { error: 'Document already assigned.' }

  const metadata = staged.raw_metadata as any
  if (!metadata) {
    return { error: 'No metadata found for this document. Please assign manually.' }
  }

  // 2. Resolve client using the shared helper (same logic as the auto pipeline)
  const { resolveClientFromIdentifiers, normalizeGSTIN, normalizePAN, normalizeFY } = await import('@/lib/actions/assignment')

  const resolvedClient = await resolveClientFromIdentifiers(supabase as any, orgId, {
    gstin: metadata.gstin ?? null,
    client_identifiers: metadata.client_identifiers ?? [],
    client_name: metadata.client_name ?? null,
  })

  let clientId: string
  let clientName: string

  if (resolvedClient) {
    clientId = resolvedClient.id
    clientName = resolvedClient.name
  } else {
    // Auto-create client — only when GSTIN or PAN present AND client name available
    const normalizedGSTIN = normalizeGSTIN(metadata.gstin)
    const extractedPAN = metadata.client_identifiers
      ?.map((identifier: string) => normalizePAN(identifier))
      .find((pan: string | null): pan is string => pan !== null) ?? null

    if (!metadata.client_name) {
      return { error: 'Could not identify client from document. Please assign manually.' }
    }
    if (!normalizedGSTIN && !extractedPAN) {
      return {
        error: 'No GSTIN or PAN found in document. Cannot auto-create client without a deterministic identifier. Please assign manually.',
      }
    }

    const pan = normalizedGSTIN
      ? normalizedGSTIN.substring(2, 12)
      : extractedPAN

    const { data: newClient, error: clientErr } = await supabase
      .from('clients')
      .insert({
        org_id: orgId,
        name: metadata.client_name,
        gstin: normalizedGSTIN,
        pan,
      })
      .select('id, name')
      .single()

    if (clientErr || !newClient) {
      return { error: clientErr?.message ?? 'Failed to create client.' }
    }
    clientId = newClient.id
    clientName = newClient.name
  }

  // 3. Resolve financial year — require an explicitly extracted FY, no hardcoded fallback
  const rawFY = selectedFy || metadata.financial_year || metadata.financial_years?.[0]
  if (!rawFY) {
    return {
      error: `Client matched (${clientName}) but no financial year found in document. Please create the matter manually under the client.`,
    }
  }
  const financialYear = normalizeFY(rawFY)
  if (financialYear === 'Unknown FY') {
    return {
      error: `Client matched (${clientName}) but could not parse financial year "${rawFY}". Please create the matter manually.`,
    }
  }

  // 4. Check if a matter already exists for this client + FY (no blind insert)
  const { data: existingMatter } = await supabase
    .from('matters')
    .select('id')
    .eq('org_id', orgId)
    .eq('client_id', clientId)
    .eq('financial_year', financialYear)
    .is('deleted_at', null)
    .maybeSingle()

  if (existingMatter) {
    // Matter already exists — just assign to it
    return assignStagedDocument(stagedId, existingMatter.id)
  }

  // 5. Create new matter
  const { generateDefaultMatterTitle } = await import('@/lib/utils/matterNaming')
  const title = await generateDefaultMatterTitle(supabase as any, orgId, clientId, clientName, financialYear)
  const description = metadata.summary || null

  const { data: newMatter, error: matterErr } = await supabase
    .from('matters')
    .insert({
      org_id: orgId,
      client_id: clientId,
      title,
      financial_year: financialYear,
      description,
      status: 'active',
    })
    .select('id')
    .single()

  if (matterErr || !newMatter) {
    return { error: matterErr?.message ?? 'Failed to create matter.' }
  }

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

  const { resolveDocumentAssignment } = await import('@/lib/actions/assignment')
  let revalidated = false

  for (const doc of staged) {
    const metadata = doc.raw_metadata as any
    if (!metadata) continue

    // Skip duplicates — they have a specific reason and the user must resolve manually
    if (doc.suggestion_reason?.startsWith('DUPLICATE:')) continue

    // Re-run the full assignment engine (Phases A1, A2, B, C)
    const result = await resolveDocumentAssignment(supabase as any, orgId, metadata)

    if (result.type === 'auto_assign') {
      const { assignments } = result
      // Update with the best suggestion found — Phase A/B matches are sufficient for the UI
      await (supabase as any)
        .from('staged_documents')
        .update({
          suggested_matter_ids: assignments.map(a => a.matterId),
          suggested_client_id: assignments[0]?.clientId ?? null,
          suggested_matter_id: assignments[0]?.matterId ?? null,
          suggestion_reason: `Re-evaluation found a match (${assignments[0]?.method ?? 'unknown'}).`,
        })
        .eq('id', doc.id)
      revalidated = true
    } else if (result.suggestions.length > 0) {
      // Partial match — update suggestions without changing the status
      await (supabase as any)
        .from('staged_documents')
        .update({
          suggested_matter_ids: result.suggestions.filter(s => s.matterId).map(s => s.matterId),
          suggested_client_id: result.suggestions.find(s => s.clientId)?.clientId ?? null,
          suggested_matter_id: result.suggestions.find(s => s.matterId)?.matterId ?? null,
          suggestion_reason: result.reason,
        })
        .eq('id', doc.id)
      revalidated = true
    }
  }

  if (revalidated) {
    revalidatePath('/inbox')
    revalidatePath('/', 'layout')
  }
}

/**
 * Service-client version of reevaluateStagedDocuments.
 * Called from trigger.dev jobs after auto-assignment to proactively
 * update suggestions for remaining staged docs without needing user auth.
 */
export async function reevaluateStagedDocumentsForOrg(orgId: string) {
  const supabase = createServiceClient()

  const { data: staged } = await supabase
    .from('staged_documents')
    .select('*')
    .eq('org_id', orgId)
    .eq('status', 'ready_to_assign')

  if (!staged || staged.length === 0) return

  const { resolveDocumentAssignment } = await import('@/lib/actions/assignment')

  for (const doc of staged) {
    const metadata = doc.raw_metadata as any
    if (!metadata) continue

    // Skip duplicates — they have a specific reason and the user must resolve manually
    if (doc.suggestion_reason?.startsWith('DUPLICATE:')) continue

    // Re-run the full assignment engine (Phases A1, A2, B, C)
    const result = await resolveDocumentAssignment(supabase as any, orgId, metadata)

    if (result.type === 'auto_assign') {
      const { assignments } = result
      await (supabase as any)
        .from('staged_documents')
        .update({
          suggested_matter_ids: assignments.map(a => a.matterId),
          suggested_client_id: assignments[0]?.clientId ?? null,
          suggested_matter_id: assignments[0]?.matterId ?? null,
          suggestion_reason: `Re-evaluation found a match (${assignments[0]?.method ?? 'unknown'}).`,
        })
        .eq('id', doc.id)
    } else if (result.suggestions.length > 0) {
      await (supabase as any)
        .from('staged_documents')
        .update({
          suggested_matter_ids: result.suggestions.filter(s => s.matterId).map(s => s.matterId),
          suggested_client_id: result.suggestions.find(s => s.clientId)?.clientId ?? null,
          suggested_matter_id: result.suggestions.find(s => s.matterId)?.matterId ?? null,
          suggestion_reason: result.reason,
        })
        .eq('id', doc.id)
    }
  }
}
