'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'
import type { Database } from '@/lib/supabase/database.types'

// ── Get Documents for a Matter ────────────────────────────────────

export async function getDocumentsByMatter(matterId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { proceedings: [], supporting: [] }

  const { data } = await supabase
    .from('documents')
    .select('*')
    .eq('matter_id', matterId)
    .eq('org_id', orgId)
    .is('deleted_at', null)
    .order('created_at', { ascending: false })

  let all = data ?? []
  const docIds = all.map(d => d.id)

  let links: any[] = []
  if (docIds.length > 0) {
    const { data: linksData } = await supabase
      .from('document_links')
      .select('*')
      .or(`from_doc_id.in.(${docIds.join(',')}),to_doc_id.in.(${docIds.join(',')})`)
    
    if (linksData) links = linksData
  }

  // Fetch cross-matter documents that are linked but not in this matter
  const linkedDocIds = new Set<string>()
  links.forEach(l => {
    if (l.from_doc_id && !docIds.includes(l.from_doc_id)) linkedDocIds.add(l.from_doc_id)
    if (l.to_doc_id && !docIds.includes(l.to_doc_id)) linkedDocIds.add(l.to_doc_id)
  })

  if (linkedDocIds.size > 0) {
    const { data: crossMatterDocs } = await supabase
      .from('documents')
      .select('*')
      .in('id', Array.from(linkedDocIds))
      .eq('org_id', orgId)
      .is('deleted_at', null)
      
    if (crossMatterDocs) {
      all = [...all, ...crossMatterDocs]
    }
  }

  return {
    proceedings: all.filter(d => d.document_class === 'proceeding' || !d.document_class),
    supporting: all.filter(d => d.document_class === 'supporting'),
    links,
  }
}

// ── Get Needs-Review Documents (for Needs Attention panel) ────────

export async function getNeedsReviewDocuments() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data } = await supabase
    .from('documents')
    .select(`
      *,
      matters(id, title, matter_code, financial_year,
        clients(id, name))
    `)
    .eq('org_id', orgId)
    .eq('status', 'needs_review')
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
    .limit(50)

  return data ?? []
}

// ── Duplicate Checking ────────────────────────────────────────────

export async function checkExactDuplicate(sha256: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: exactDup, error } = await supabase
    .from('documents')
    .select('id, reference_number, matters(title)')
    .eq('org_id', orgId)
    .eq('file_hash_sha256', sha256)
    .is('deleted_at', null)
    .maybeSingle()

  if (error) {
    console.error('Error checking duplicate:', error)
    return { error: 'Failed to check duplicates.' }
  }

  if (exactDup) {
    const matterTitle = (exactDup as any).matters?.title || 'Unknown Matter'
    const refNum = exactDup.reference_number || exactDup.id
    return { 
      isDuplicate: true, 
      duplicateOf: { id: exactDup.id, reference: refNum, matterTitle } 
    }
  }

  return { isDuplicate: false }
}

// ── Upload Directly to a Matter ───────────────────────────────────

export async function uploadToMatter(matterId: string, formData: FormData) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const file = formData.get('file') as File
  if (!file) return { error: 'No file provided.' }

  const allowedTypes = ['application/pdf']
  if (!allowedTypes.includes(file.type)) {
    return { error: 'Only PDF files are supported.' }
  }

  const maxSize = 50 * 1024 * 1024 // 50MB
  if (file.size > maxSize) {
    return { error: 'File must be under 50MB.' }
  }

  // Verify matter belongs to this org
  const { data: matter } = await supabase
    .from('matters')
    .select('id, status')
    .eq('id', matterId)
    .eq('org_id', orgId)
    .single()

  if (!matter) return { error: 'Matter not found.' }

  const fileName = `${orgId}/${matterId}/${Date.now()}_${file.name.replace(/\s/g, '_')}`

  const { error: uploadError } = await supabase.storage
    .from('documents')
    .upload(fileName, file, { contentType: file.type })

  if (uploadError) {
    console.error('Storage upload error:', uploadError)
    return { error: uploadError.message }
  }

  const { data: doc, error: docError } = await supabase
    .from('documents')
    .insert({
      matter_id: matterId,
      org_id: orgId,
      storage_path: fileName,
      status: 'processing',
      source: 'direct',
      created_by: user.id,
    })
    .select('id')
    .single()

  if (docError || !doc) {
    // Clean up storage if DB insert fails
    await supabase.storage.from('documents').remove([fileName])
    console.error('Document insert error:', docError)
    return { error: docError?.message ?? 'Failed to create document record.' }
  }

  // TODO: Trigger process-document job via Trigger.dev
  // await tasks.trigger('process-document', { documentId: doc.id, matterId, source: 'direct' })

  revalidatePath(`/matters/${matterId}`)
  return { success: true, documentId: doc.id }
}

// ── Reassign Document to a Different Matter ───────────────────────

export async function reassignDocumentMatter(
  documentId: string,
  newMatterId: string,
) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  // Fetch current document
  const { data: doc } = await supabase
    .from('documents')
    .select('id, matter_id, org_id')
    .eq('id', documentId)
    .eq('org_id', orgId)
    .single()

  if (!doc) return { error: 'Document not found.' }
  if (doc.matter_id === newMatterId) return { error: 'Document is already in this matter.' }

  const oldMatterId = doc.matter_id

  // Verify new matter belongs to this org
  const { data: newMatter } = await supabase
    .from('matters')
    .select('id')
    .eq('id', newMatterId)
    .eq('org_id', orgId)
    .single()

  if (!newMatter) return { error: 'Target matter not found.' }

  // 1. Delete existing document_links (built in wrong matter's scope)
  await supabase
    .from('document_links')
    .delete()
    .or(`from_doc_id.eq.${documentId},to_doc_id.eq.${documentId}`)

  // 2. Reassign document
  const { error: updateError } = await supabase
    .from('documents')
    .update({
      matter_id: newMatterId,
      status: 'processing',    // re-queue for chaining
      review_reason: null,
      source: 'inbox',         // treated as confirmed, skips routing check
    })
    .eq('id', documentId)

  if (updateError) {
    console.error('Reassign document error:', updateError)
    return { error: updateError.message }
  }

  // 3. Update any deadlines tied to this document
  await supabase
    .from('deadlines')
    .update({ matter_id: newMatterId })
    .eq('matter_id', oldMatterId)
    // Note: deadlines don't have a document_id FK in current schema,
    // they are scoped to matters. No update needed unless we add that FK later.

  // 4. Log reversible activity
  await supabase
    .from('activity_logs')
    .insert({
      org_id: orgId,
      user_id: user.id,
      action: 'document_reassigned',
      entity_type: 'document',
      entity_id: documentId,
      is_reversible: true,
      metadata: {
        old_matter_id: oldMatterId,
        new_matter_id: newMatterId,
      },
    })

  // 5. Re-trigger processing (chaining in new matter's scope)
  // await tasks.trigger('process-document', { documentId, matterId: newMatterId, source: 'inbox' })

  revalidatePath(`/matters/${oldMatterId}`)
  revalidatePath(`/matters/${newMatterId}`)
  revalidatePath('/inbox')
  return { success: true }
}

// ── Dismiss Needs-Review Flag ─────────────────────────────────────

export async function dismissReviewFlag(documentId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { error } = await supabase
    .from('documents')
    .update({
      status: 'analyzed',
      review_reason: null,
    })
    .eq('id', documentId)
    .eq('org_id', orgId)

  if (error) {
    console.error('Dismiss review flag error:', error)
    return { error: error.message }
  }

  revalidatePath('/inbox')
  return { success: true }
}

// ── Promote / Demote document class ──────────────────────────────

export async function setDocumentClass(
  documentId: string,
  newClass: 'proceeding' | 'supporting',
) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  // Get current class to decide if we need to clean up chains
  const { data: doc } = await supabase
    .from('documents')
    .select('id, document_class, matter_id')
    .eq('id', documentId)
    .eq('org_id', orgId)
    .single()

  if (!doc) return { error: 'Document not found.' }

  // If demoting from proceeding → supporting: delete its chains
  if (doc.document_class === 'proceeding' && newClass === 'supporting') {
    await supabase
      .from('document_links')
      .delete()
      .or(`from_doc_id.eq.${documentId},to_doc_id.eq.${documentId}`)
  }

  const { error } = await supabase
    .from('documents')
    .update({
      document_class: newClass,
      // If promoting to proceeding, re-queue for chaining
      status: newClass === 'proceeding' ? 'processing' : 'analyzed',
    })
    .eq('id', documentId)
    .eq('org_id', orgId)

  if (error) {
    console.error('Set document class error:', error)
    return { error: error.message }
  }

  // If promoting → re-trigger chaining
  // if (newClass === 'proceeding') {
  //   await tasks.trigger('process-document', { documentId, matterId: doc.matter_id, source: 'inbox', stepsOnly: ['chaining'] })
  // }

  revalidatePath(`/matters/${doc.matter_id}`)
  return { success: true }
}

// ── Secure Signed URL Generator ───────────────────────────────────

export async function getDocumentSignedUrl(bucket: 'documents' | 'staging', path: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { data, error } = await supabase.storage
    .from(bucket)
    .createSignedUrl(path, 60 * 15) // 15 mins valid

  if (error || !data) {
    console.error('Failed to create signed URL:', error)
    return { error: error?.message ?? 'Failed to generate view link.' }
  }

  return { url: data.signedUrl }
}


export async function updateDocumentMetadata(docId: string, metadataKey: string, newValue: any) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  // Get current metadata
  const { data: doc } = await supabase
    .from('documents')
    .select('raw_metadata, matter_id')
    .eq('id', docId)
    .eq('org_id', orgId)
    .single()

  if (!doc) return { error: 'Document not found' }

  let currentMetadata = doc.raw_metadata as any || {}
  
  const columnMap: Record<string, string> = {
    doc_type: 'doc_type',
    reference_number: 'reference_number',
    doc_date: 'doc_date',
    financial_year: 'financial_year',
    tax_period: 'tax_period',
  }

  const updatePayload: any = {}

  if (metadataKey.includes('.')) {
    // nested update for extracted_amounts
    const [parent, child] = metadataKey.split('.')
    if (!currentMetadata[parent]) currentMetadata[parent] = {}
    currentMetadata[parent][child] = newValue
  } else {
    currentMetadata[metadataKey] = newValue
    if (columnMap[metadataKey]) {
      updatePayload[columnMap[metadataKey]] = newValue
    }
  }

  updatePayload.raw_metadata = currentMetadata

  const { error } = await supabase
    .from('documents')
    .update(updatePayload)
    .eq('id', docId)

  if (error) return { error: error.message }

  const { revalidatePath } = require('next/cache')
  if (doc.matter_id) {
    revalidatePath(`/matters/${doc.matter_id}`)
  }
  
  return { success: true }
}

export async function createManualLink(
  fromDocId: string,
  toDocId: string,
  linkType: Database['public']['Enums']['link_type']
) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  // Check if link exists
  const { data: existing } = await supabase.from('document_links')
    .select('id')
    .eq('from_doc_id', fromDocId)
    .eq('to_doc_id', toDocId)
    .maybeSingle()

  if (existing) {
    return { error: 'Link already exists between these documents' }
  }

  const db = createServiceClient()

  const { error } = await db.from('document_links').insert({
    from_doc_id: fromDocId,
    to_doc_id: toDocId,
    link_type: linkType,
    confidence: 1.0,
    status: 'confirmed',
    match_method: 'manual',
    created_by: user.id
  })

  if (error) return { error: error.message }

  // Fetch document details for human readable log description
  const { data: docs } = await db
    .from('documents')
    .select('id, doc_type, reference_number, matters(title)')
    .in('id', [fromDocId, toDocId])

  const fromDoc = docs?.find(d => d.id === fromDocId)
  const toDoc = docs?.find(d => d.id === toDocId)
  const fromType = fromDoc?.doc_type || fromDoc?.reference_number || 'Document'
  const toType = toDoc?.doc_type || toDoc?.reference_number || 'Document'
  const caseName = (fromDoc?.matters as any)?.title || (toDoc?.matters as any)?.title || 'Matter'

  // Log activity with normalized IDs (dynamic resolution)
  await db.from('activity_logs').insert({
    org_id: orgId,
    user_id: user.id,
    action: 'manual_link_created',
    entity_type: 'document_link',
    description: `Manually linked documents`,
    metadata: {
      from_doc_id: fromDocId,
      to_doc_id: toDocId,
      link_type: linkType
    },
    is_reversible: true
  })

  return { success: true }
}

export async function deleteDocumentLink(linkId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const db = createServiceClient()

  // Fetch link IDs before deletion
  const { data: link } = await db
    .from('document_links')
    .select('id, from_doc_id, to_doc_id')
    .eq('id', linkId)
    .single()

  const { error } = await db
    .from('document_links')
    .delete()
    .eq('id', linkId)

  if (error) return { error: error.message }

  await db.from('activity_logs').insert({
    org_id: orgId,
    user_id: user.id,
    action: 'manual_link_deleted',
    entity_type: 'document_link',
    description: `Deleted document link`,
    metadata: {
      from_doc_id: link?.from_doc_id,
      to_doc_id: link?.to_doc_id
    },
    is_reversible: false
  })

  return { success: true }
}

export async function deleteDocument(documentId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const db = createServiceClient()

  const { data: doc } = await db
    .from('documents')
    .select('id, matter_id, reference_number')
    .eq('id', documentId)
    .eq('org_id', orgId)
    .single()

  if (!doc) return { error: 'Document not found.' }

  // 1. Soft delete associated case notes
  await db
    .from('case_notes')
    .update({ deleted_at: new Date().toISOString() })
    .eq('document_id', documentId)
    .eq('org_id', orgId)

  // 2. Soft delete document (links remain in system for future restoration)
  const { error } = await db
    .from('documents')
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', documentId)
    .eq('org_id', orgId)

  if (error) {
    console.error('Delete document error:', error)
    return { error: error.message }
  }

  // 4. Log activity
  await db.from('activity_logs').insert({
    org_id: orgId,
    user_id: user.id,
    action: 'document_deleted',
    entity_type: 'document',
    entity_id: documentId,
    description: `Deleted document ${doc.reference_number || doc.id}`,
    is_reversible: true
  })

  // 5. Re-evaluate remaining matter links
  if (doc.matter_id) {
    const { reevaluateMatterLinks } = require('@/lib/actions/chaining')
    await reevaluateMatterLinks(db, doc.matter_id, orgId, user.id)
    revalidatePath(`/matters/${doc.matter_id}`)
  }

  revalidatePath('/matters')
  return { success: true }
}

