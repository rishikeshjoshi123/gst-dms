'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'
import { after } from 'next/server'
import type { Database } from '@/lib/supabase/database.types'
import { tasks } from '@trigger.dev/sdk/v3'
import { appendActivity } from '@/lib/activity'
import {
  observeStoredPdf,
  ownsTerminalUploadCleanup,
  storageDeletionWasRecorded,
  uploadFailureResult,
  uploadIdempotencyKey,
} from '@/lib/document-upload'

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
  return uploadToDocumentIntake(formData, matterId)
}

/**
 * Stores a PDF through the one canonical reservation/finalisation pipeline.
 * An omitted intended matter deliberately leaves the intake unassigned for
 * global Inbox triage; the browser never writes a storage path or intake row.
 */
export async function uploadToDocumentIntake(formData: FormData, intendedMatterId: string | null = null) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return uploadFailureResult('No active organisation.', 'terminal')

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return uploadFailureResult('Not authenticated.', 'terminal')

  const file = formData.get('file') as File
  if (!file) return uploadFailureResult('No file provided.', 'terminal')

  const idempotencyKey = uploadIdempotencyKey(formData.get('upload_idempotency_key'))
  if (!idempotencyKey) return uploadFailureResult('This upload could not be prepared. Please choose the file again.', 'terminal')
  const { data: reservations, error: reservationError } = await supabase.rpc('reserve_document_upload', {
    p_filename: file.name,
    p_mime: 'application/pdf',
    p_declared_bytes: file.size,
    p_intended_matter: intendedMatterId as string,
    p_idempotency: idempotencyKey,
  })
  const reservation = reservations?.[0]

  if (reservationError || !reservation) {
    console.error('Document upload reservation failed:', reservationError)
    return uploadFailureResult('Could not reserve this upload. Please try again.')
  }
  if (reservation.code !== 'ok' || !reservation.upload_session_id || !reservation.intake_item_id || !reservation.bucket_id || !reservation.object_key) {
    return uploadFailureResult(
      documentUploadError(reservation.code),
      reservation.code === 'platform_capacity_unavailable' ? 'retry' : 'terminal',
    )
  }

  const storage = createServiceClient()
  const recordObservedBytes = async (observedBytes: number) => {
    const { data, error } = await storage.rpc('record_document_upload_observed_bytes', {
      p_session: reservation.upload_session_id,
      p_observed_bytes: observedBytes,
    })
    if (error || data?.[0]?.code !== 'ok') {
      // Keep the session and object retryable. Terminalising it with a
      // browser-declared size could undercount if physical deletion fails.
      console.error('Document upload observed bytes could not be recorded:', error ?? data?.[0]?.code)
      return false
    }
    return true
  }
  const recordStorageDeletion = async () => {
    const { data, error } = await storage.rpc('record_document_asset_storage_deleted', {
      p_asset_id: reservation.asset_id,
    })
    const code = data?.[0]?.code
    if (error || !storageDeletionWasRecorded(code)) {
      // The object has gone, but until the durable tombstone is recorded we
      // intentionally continue to count it against quota. The scheduled
      // terminal-asset cleaner can reconcile this safely.
      console.error('Document asset deletion could not be recorded:', error ?? code)
      return false
    }
    return true
  }
  const removeTerminalAsset = async () => {
    const { error } = await storage.storage.from(reservation.bucket_id).remove([reservation.object_key])
    if (error) {
      // A failed physical deletion must remain counted; do not tombstone it.
      console.error('Terminal document asset could not be deleted:', error)
      return false
    }
    return recordStorageDeletion()
  }
  const failUpload = async (errorCode: 'upload_failed' | 'invalid_pdf' | 'storage_missing' | 'upload_rejected') => {
    const { data, error } = await storage.rpc('fail_document_upload', {
      p_session: reservation.upload_session_id,
      // `validation_failed` is the durable lifecycle code for a server-read
      // object rejected by completion policy; `upload_rejected` is only a UI
      // categorisation and is not accepted by the database command.
      p_error_code: errorCode === 'upload_rejected' ? 'validation_failed' : errorCode,
      p_idempotency: idempotencyKey,
    })
    const code = data?.[0]?.code
    if (error || !ownsTerminalUploadCleanup(code)) {
      // Do not remove the only copy unless the lifecycle has durably recorded
      // a terminal state. In particular, `not_available` can be a concurrent
      // finalisation that made this asset available and referenceable.
      console.error('Document upload failure could not be recorded:', error ?? code)
      return false
    }
    await removeTerminalAsset()
    return true
  }

  const { error: uploadError } = await storage.storage
    .from(reservation.bucket_id)
    .upload(reservation.object_key, file, { contentType: 'application/pdf', upsert: false })
  // An object may already exist when a request timed out after Storage accepted
  // the bytes. Read the reserved key before treating that retry as a failure.
  const { data: storedObject, error: downloadError } = await storage.storage
    .from(reservation.bucket_id)
    .download(reservation.object_key)
  if (downloadError || !storedObject) {
    console.error('Reserved document storage upload or observation failed:', uploadError ?? downloadError)
    const terminalised = await failUpload(uploadError ? 'upload_failed' : 'storage_missing')
    return terminalised
      ? uploadFailureResult(uploadError ? 'The PDF upload did not complete.' : 'The uploaded PDF could not be verified.', 'terminal')
      : uploadFailureResult('The uploaded PDF could not be recorded safely. Retry this file.')
  }

  const observation = await observeStoredPdf(storedObject)
  if (!observation.ok) {
    if (!await recordObservedBytes(observation.byteSize)) {
      return uploadFailureResult('The uploaded PDF could not be recorded safely. Retry this file.')
    }
    const terminalised = await failUpload('invalid_pdf')
    return terminalised
      ? uploadFailureResult('The uploaded file is not a valid PDF.', 'terminal')
      : uploadFailureResult('The uploaded PDF could not be recorded safely. Retry this file.')
  }

  const { data: completions, error: completionError } = await storage.rpc('complete_document_upload', {
    p_session: reservation.upload_session_id,
    p_observed_bytes: observation.byteSize,
    p_sha256: observation.sha256,
    p_detected_mime: observation.detectedMime,
    p_idempotency: idempotencyKey,
  })
  const completion = completions?.[0]
  if (completionError || !completion) {
    console.error('Document upload completion failed:', completionError)
    // The database may have committed despite an interrupted RPC response.
    // Leave this reserved key intact so the same idempotency key can complete.
    return uploadFailureResult('The uploaded PDF could not be finalised. Retry this file.')
  }
  if (completion.code !== 'ok') {
    if (completion.code === 'duplicate') {
      await removeTerminalAsset()
      return uploadFailureResult(documentUploadError(completion.code), 'duplicate')
    } else {
      // Policy/finalisation rejections are terminal. Persist their declared
      // server-observed bytes before releasing the reservation so a failed
      // physical deletion cannot evade organisation or platform accounting.
      if (!await recordObservedBytes(observation.byteSize)) {
        return uploadFailureResult('The uploaded PDF could not be recorded safely. Retry this file.')
      }
      const terminalised = await failUpload('upload_rejected')
      if (!terminalised) {
        return uploadFailureResult('The uploaded PDF could not be recorded safely. Retry this file.')
      }
      return uploadFailureResult(documentUploadError(completion.code), 'terminal')
    }
  }

  // complete_document_upload writes the validation event in the same database
  // transaction. The outbox dispatcher, rather than this request, starts work.
  revalidatePath('/inbox')
  if (intendedMatterId) revalidatePath(`/matters/${intendedMatterId}`)
  return { success: true, intakeId: completion.intake_item_id }
}

function documentUploadError(code: string) {
  switch (code) {
    case 'invalid_matter': return 'Matter not found or no longer active.'
    case 'file_too_large': return 'File exceeds the organisation upload limit.'
    case 'organisation_quota_exceeded': return 'Your organisation has reached its storage limit.'
    case 'platform_capacity_unavailable': return 'Uploads are temporarily unavailable. Please try again later.'
    case 'duplicate': return 'This PDF already exists in this organisation.'
    case 'invalid_filename': return 'Choose a PDF filename that ends in .pdf.'
    case 'invalid_mime': return 'Only PDF files are supported.'
    default: return 'Could not prepare this upload. Please try again.'
  }
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

  let documentToProcess: { id: string; matterId: string; storagePath: string } | null = null

  if (mode === 'copy') {
    if (!doc.storage_path) {
      return { error: 'This document has no file attached, so it cannot be copied yet.' }
    }

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
    documentToProcess = { id: newDoc.id, matterId: newMatterId, storagePath: copiedStoragePath }

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
    const moveUpdate = doc.storage_path
      ? {
          matter_id: newMatterId,
          status: 'processing' as const,
          review_reason: null,
          source: 'inbox',
        }
      : { matter_id: newMatterId }

    const { error: updateError } = await supabase
      .from('documents')
      .update(moveUpdate)
      .eq('id', documentId)

    if (updateError) {
      console.error('Reassign document error:', updateError)
      return { error: updateError.message }
    }
    if (doc.storage_path) {
      documentToProcess = { id: documentId, matterId: newMatterId, storagePath: doc.storage_path }
    }

    // 3. Update any deadlines tied to this document
    await supabase
      .from('deadlines')
      .update({ matter_id: newMatterId })
      .eq('document_id', documentId)

    // 4. Log reversible activity
    await appendActivity({
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
      storagePath: documentToProcess.storagePath,
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
    .select('id, document_class, matter_id, storage_path, created_by, status')
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

  const nextStatus = doc.storage_path
    ? (newClass === 'proceeding' ? 'processing' : 'analyzed')
    : doc.status

  const { error } = await supabase
    .from('documents')
    .update({
      document_class: newClass,
      status: nextStatus,
    })
    .eq('id', documentId)
    .eq('org_id', orgId)

  if (error) {
    console.error('Set document class error:', error)
    return { error: error.message }
  }

  if (newClass === 'proceeding' && doc.storage_path) {
    const queued = await enqueueDocumentProcessing({
      id: documentId,
      matterId: doc.matter_id,
      orgId,
      storagePath: doc.storage_path,
      uploadedBy: doc.created_by ?? '',
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

/**
 * Generate a short-lived PDF URL from an authorised immutable version. The
 * version lookup happens under the user's RLS context; callers never provide a
 * Storage path, and the service client sees it only after that grant succeeds.
 */
export async function getDocumentVersionSignedUrl(documentVersionId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { data: grants, error: grantError } = await supabase.rpc('get_document_version_read_grant', {
    p_document_version_id: documentVersionId,
  })
  const grant = grants?.[0]
  if (grantError || !grant || grant.code !== 'ok' || !grant.bucket_id || !grant.object_key) {
    return { error: 'This document version is not available.' }
  }

  const storage = createServiceClient()
  const { data, error } = await storage.storage
    .from(grant.bucket_id)
    .createSignedUrl(grant.object_key, 60 * 15)

  if (error || !data) {
    console.error('Failed to create versioned document URL:', error)
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
  await appendActivity({
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

  await appendActivity({
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
  await appendActivity({
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
