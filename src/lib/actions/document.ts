'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'
import { after } from 'next/server'
import type { Database } from '@/lib/supabase/database.types'
import { tasks } from '@trigger.dev/sdk/v3'
import { appendActivity } from '@/lib/activity'

async function enqueueDocumentProcessing(
  document: { id: string; matterId: string; orgId: string; storagePath: string; uploadedBy: string },
  options: { reprocessMode?: 'metadata_only' | 'full'; skipDuplicateCheck?: boolean } = {},
) {
  // The document row is already durable. Trigger the long-running job only
  // after this Server Action responds, so an intermittent task gateway never
  // blocks the caller's UI from returning to the matter timeline.
  after(async () => {
    try {
      await tasks.trigger('process-document', {
        docId: document.id,
        matterId: document.matterId,
        orgId: document.orgId,
        storagePath: document.storagePath,
        uploadedBy: document.uploadedBy,
        reprocessMode: options.reprocessMode ?? 'full',
        skipDuplicateCheck: options.skipDuplicateCheck ?? false,
      })
    } catch (error) {
      console.error('Failed to queue document processing:', error)
      const serviceClient = createServiceClient()
      await serviceClient
        .from('documents')
        .update({ status: 'failed', review_reason: 'Processing could not be queued. Retry this document.' })
        .eq('id', document.id)
        .eq('org_id', document.orgId)
    }
  })

  return { success: true as const }
}

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
  const { createHash } = await import('crypto')
  const fileHash = createHash('sha256').update(Buffer.from(await file.arrayBuffer())).digest('hex')

  const { data: duplicate } = await supabase
    .from('documents')
    .select('id')
    .eq('org_id', orgId)
    .eq('file_hash_sha256', fileHash)
    .is('deleted_at', null)
    .maybeSingle()

  if (duplicate) return { error: 'This file has already been uploaded to this organisation.' }

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
      file_hash_sha256: fileHash,
    })
    .select('id')
    .single()

  if (docError || !doc) {
    // Clean up storage if DB insert fails
    await supabase.storage.from('documents').remove([fileName])
    console.error('Document insert error:', docError)
    return { error: docError?.message ?? 'Failed to create document record.' }
  }

  const queued = await enqueueDocumentProcessing({
    id: doc.id,
    matterId,
    orgId,
    storagePath: fileName,
    uploadedBy: user.id,
  })

  revalidatePath(`/matters/${matterId}`)
  if ('error' in queued) return queued
  return { success: true, documentId: doc.id }
}

// ── Reassign Document to a Different Matter ───────────────────────

export async function reassignDocumentMatter(
  documentId: string,
  newMatterId: string,
  mode: 'move' | 'copy' = 'move'
) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  // Fetch current document
  const { data: doc } = await supabase
    .from('documents')
    .select('*')
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

  let documentToProcess: { id: string; matterId: string } | null = null
  let processingStoragePath = doc.storage_path

  if (mode === 'copy') {
    const originalName = doc.storage_path.split('/').pop() || 'document.pdf'
    const copiedStoragePath = `${orgId}/${newMatterId}/${Date.now()}_${originalName}`
    const { data: sourceFile, error: sourceFileError } = await supabase.storage
      .from('documents')
      .download(doc.storage_path)

    if (sourceFileError || !sourceFile) {
      return { error: 'Could not read the original document file.' }
    }

    const { error: copyFileError } = await supabase.storage
      .from('documents')
      .upload(copiedStoragePath, sourceFile, { contentType: 'application/pdf' })

    if (copyFileError) return { error: 'Could not copy the document file to the target matter.' }

    const { error: insertError, data: newDoc } = await supabase
      .from('documents')
      .insert({
        org_id: orgId,
        matter_id: newMatterId,
        storage_path: copiedStoragePath,
        status: 'processing', // re-queue for chaining
        review_status: 'unreviewed',
        source: 'inbox',
        created_by: user.id,
        doc_type: doc.doc_type,
        reference_number: doc.reference_number,
        doc_date: doc.doc_date,
        direction: doc.direction,
        document_class: doc.document_class,
        document_category: doc.document_category,
        financial_year: doc.financial_year,
        raw_metadata: doc.raw_metadata,
        file_hash_sha256: doc.file_hash_sha256
      })
      .select('id')
      .single()

    if (insertError || !newDoc) {
      await supabase.storage.from('documents').remove([copiedStoragePath])
      console.error('Copy document error:', insertError)
      return { error: insertError?.message ?? 'Failed to copy document' }
    }
    documentToProcess = { id: newDoc.id, matterId: newMatterId }
    processingStoragePath = copiedStoragePath

    // Log reversible activity
    await appendActivity({
        org_id: orgId,
        user_id: user.id,
        action: 'document_copied',
        entity_type: 'document',
        entity_id: newDoc.id,
        is_reversible: true,
        metadata: {
          original_document_id: documentId,
          original_matter_id: oldMatterId,
          new_matter_id: newMatterId,
        },
      })
  } else {
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
    documentToProcess = { id: documentId, matterId: newMatterId }

    // 3. Update any deadlines tied to this document
    await supabase
      .from('deadlines')
      .update({ matter_id: newMatterId })
      .eq('document_id', documentId)

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
  }

  if (documentToProcess) {
    const queued = await enqueueDocumentProcessing({
      id: documentToProcess.id,
      matterId: documentToProcess.matterId,
      orgId,
      storagePath: processingStoragePath,
      uploadedBy: user.id,
      // Metadata already exists, so this re-runs placement without paying for AI again.
    }, { skipDuplicateCheck: true })
    if ('error' in queued) return queued
  }

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

  if (newClass === 'proceeding') {
    const fullDoc = await supabase
      .from('documents')
      .select('storage_path, created_by')
      .eq('id', documentId)
      .eq('org_id', orgId)
      .single()
    if (!fullDoc.data) return { error: 'Document not found.' }
    const queued = await enqueueDocumentProcessing({
      id: documentId,
      matterId: doc.matter_id,
      orgId,
      storagePath: fullDoc.data.storage_path,
      uploadedBy: fullDoc.data.created_by ?? '',
    }, { skipDuplicateCheck: true })
    if ('error' in queued) return queued
  }

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

  // Never treat a bucket/path received from the browser as authorization. The
  // row lookup is scoped by the active organisation and still respects RLS.
  // This also permits legacy document rows that used a shared storage path to
  // be read through a controlled, short-lived URL.
  const recordQuery = bucket === 'documents'
    ? supabase
      .from('documents')
      .select('id')
      .eq('org_id', orgId)
      .eq('storage_path', path)
      .is('deleted_at', null)
      .maybeSingle()
    : supabase
      .from('staged_documents')
      .select('id')
      .eq('org_id', orgId)
      .eq('storage_path', path)
      .maybeSingle()

  const { data: record, error: recordError } = await recordQuery
  if (recordError || !record) {
    return { error: 'Document is not available in this organisation.' }
  }

  const storage = createServiceClient()
  const { data, error } = await storage.storage
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

  if (fromDocId === toDocId) return { error: 'A document cannot be linked to itself.' }

  // Verify both endpoints through the caller-scoped client before any write.
  // Do not use the service role for an ID supplied by the browser.
  const { data: endpoints } = await supabase
    .from('documents')
    .select('id, matter_id')
    .in('id', [fromDocId, toDocId])
    .eq('org_id', orgId)
    .is('deleted_at', null)

  if (!endpoints || endpoints.length !== 2) {
    return { error: 'One or both documents could not be found in this organisation.' }
  }

  // Check if link exists
  const { data: existing } = await supabase.from('document_links')
    .select('id')
    .eq('from_doc_id', fromDocId)
    .eq('to_doc_id', toDocId)
    .maybeSingle()

  if (existing) {
    return { error: 'Link already exists between these documents' }
  }

  const { error } = await supabase.from('document_links').insert({
    from_doc_id: fromDocId,
    to_doc_id: toDocId,
    link_type: linkType,
    confidence: 1.0,
    status: 'confirmed',
    match_method: 'manual',
    created_by: user.id
  })

  if (error) return { error: error.message }

  // Fetch document details for human readable log description + matter_id for cache revalidation
  await supabase.from('activity_logs').insert({
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

  // Revalidate the matter page so server component re-fetches fresh link data
  const matterId = endpoints.find(doc => doc.id === fromDocId)?.matter_id
  if (matterId) {
    revalidatePath(`/matters/${matterId}`)
  }

  return { success: true }
}

export async function deleteDocumentLink(linkId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  // RLS derives access from the source document; do not elevate this
  // browser-controlled identifier to the service role.
  const { data: link } = await supabase
    .from('document_links')
    .select('id, from_doc_id, to_doc_id')
    .eq('id', linkId)
    .single()

  if (!link) return { error: 'Link not found' }

  const { error } = await supabase
    .from('document_links')
    .delete()
    .eq('id', linkId)

  if (error) return { error: error.message }

  await supabase.from('activity_logs').insert({
    org_id: orgId,
    user_id: user.id,
    action: 'manual_link_deleted',
    entity_type: 'document_link',
    description: `Deleted document link`,
    metadata: {
      from_doc_id: link.from_doc_id,
      to_doc_id: link.to_doc_id
    },
    is_reversible: false
  })

  // Fetch matter_id from one of the linked documents for cache revalidation
  const { data: docData } = await supabase
    .from('documents')
    .select('matter_id')
    .eq('id', link.from_doc_id)
    .maybeSingle()

  if (docData?.matter_id) {
    revalidatePath(`/matters/${docData.matter_id}`)
  }

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
