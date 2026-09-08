'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'
import type { Database } from '@/lib/supabase/database.types'
import { appendActivity } from '@/lib/activity'
import { scheduleDocumentOutboxWake } from '@/lib/outbox/wake'
import {
  observeStoredPdf,
  ownsTerminalUploadCleanup,
  storageDeletionWasRecorded,
  uploadFailureResult,
  uploadIdempotencyKey,
} from '@/lib/document-upload'
import { canonicalDocumentPath } from '@/lib/canonical-document-route'
import { getCanonicalAssignedDocument } from '@/lib/trash/exact-resource'

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
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .order('created_at', { ascending: false })

  let all = data ?? []
  const docIds = all.map(d => d.id)

  let links: Database['public']['Tables']['document_links']['Row'][] = []
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
      .eq('record_state', 'active')
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
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
    .limit(50)

  return data ?? []
}

// ── Upload Directly to a Matter ───────────────────────────────────

type DocumentUploadReservationInput = {
  filename: string
  declaredBytes: number
  intendedMatterId: string | null
  idempotencyKey: string
}

type DocumentUploadFinalizationInput = {
  uploadSessionId: string
  idempotencyKey: string
}

/** Reserve canonical lifecycle rows before the browser transfers any bytes. */
export async function reserveDocumentUpload(input: DocumentUploadReservationInput) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return uploadFailureResult('No active organisation.', 'terminal')

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return uploadFailureResult('Not authenticated.', 'terminal')

  const idempotencyKey = uploadIdempotencyKey(input.idempotencyKey)
  const intendedMatterId = input.intendedMatterId === null ? null : uploadIdempotencyKey(input.intendedMatterId)
  if (
    !idempotencyKey
    || typeof input.filename !== 'string'
    || !Number.isSafeInteger(input.declaredBytes)
    || input.declaredBytes <= 0
    || (input.intendedMatterId !== null && !intendedMatterId)
  ) {
    return uploadFailureResult('This upload could not be prepared. Please choose the file again.', 'terminal')
  }
  const { data: reservations, error: reservationError } = await supabase.rpc('reserve_document_upload', {
    p_filename: input.filename,
    p_mime: 'application/pdf',
    p_declared_bytes: input.declaredBytes,
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
  const { data: signedUpload, error: signedUploadError } = await storage.storage
    .from(reservation.bucket_id)
    .createSignedUploadUrl(reservation.object_key, { upsert: false })

  if (signedUploadError || !signedUpload) {
    console.error('Document signed upload URL creation failed:', signedUploadError)
    return uploadFailureResult('Could not prepare the private upload. Please try again.')
  }

  return {
    success: true as const,
    uploadSessionId: reservation.upload_session_id,
    intakeId: reservation.intake_item_id,
    bucketName: reservation.bucket_id,
    objectName: reservation.object_key,
    signedUploadToken: signedUpload.token,
    tusEndpoint: resumableStorageEndpoint(),
    expiresAt: reservation.expires_at,
  }
}

/** Observe and finalise the exact reserved object after its direct transfer. */
export async function finalizeDocumentUpload(input: DocumentUploadFinalizationInput) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return uploadFailureResult('No active organisation.', 'terminal')

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return uploadFailureResult('Not authenticated.', 'terminal')

  const idempotencyKey = uploadIdempotencyKey(input.idempotencyKey)
  const uploadSessionId = uploadIdempotencyKey(input.uploadSessionId)
  if (!idempotencyKey || !uploadSessionId) return uploadFailureResult('This upload could not be finalised safely.', 'terminal')

  const storage = createServiceClient()
  const { data: session, error: sessionError } = await storage
    .from('upload_sessions')
    .select('id, asset_id, state, expires_at')
    .eq('id', uploadSessionId)
    .eq('org_id', orgId)
    .eq('created_by', user.id)
    .eq('idempotency_key', idempotencyKey)
    .maybeSingle()

  if (sessionError || !session || session.state !== 'reserved' || new Date(session.expires_at).getTime() <= Date.now()) {
    return uploadFailureResult('This upload reservation is no longer available.', 'terminal')
  }

  const { data: asset, error: assetError } = await storage
    .from('file_assets')
    .select('id, bucket_id, object_key')
    .eq('id', session.asset_id)
    .eq('org_id', orgId)
    .eq('availability', 'reserved')
    .maybeSingle()

  if (assetError || !asset) return uploadFailureResult('This upload reservation is no longer available.', 'terminal')
  const { data: intake } = await storage
    .from('intake_items')
    .select('intended_matter_id')
    .eq('upload_session_id', uploadSessionId)
    .eq('org_id', orgId)
    .maybeSingle()

  const recordObservedBytes = async (observedBytes: number) => {
    const { data, error } = await storage.rpc('record_document_upload_observed_bytes', {
      p_session: uploadSessionId,
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
      p_asset_id: asset.id,
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
    const { error } = await storage.storage.from(asset.bucket_id).remove([asset.object_key])
    if (error) {
      // A failed physical deletion must remain counted; do not tombstone it.
      console.error('Terminal document asset could not be deleted:', error)
      return false
    }
    return recordStorageDeletion()
  }
  const failUpload = async (errorCode: 'upload_failed' | 'invalid_pdf' | 'storage_missing' | 'upload_rejected') => {
    const { data, error } = await storage.rpc('fail_document_upload', {
      p_session: uploadSessionId,
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

  const { data: storedObject, error: downloadError } = await storage.storage
    .from(asset.bucket_id)
    .download(asset.object_key)
  if (downloadError || !storedObject) {
    console.error('Reserved document storage observation failed:', downloadError)
    await failUpload('storage_missing')
    return uploadFailureResult('The uploaded PDF could not be verified. Retry this file.')
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
    p_session: uploadSessionId,
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
  // transaction. The fixed singleton wake is only a latency hint: the outbox
  // and scheduled recovery remain the authority if the gateway is unavailable.
  scheduleDocumentOutboxWake()
  revalidatePath('/documents')
  revalidatePath('/', 'layout')
  if (intake?.intended_matter_id) revalidatePath(`/matters/${intake.intended_matter_id}`)
  return { success: true, intakeId: completion.intake_item_id }
}

function resumableStorageEndpoint() {
  const base = new URL(process.env.NEXT_PUBLIC_SUPABASE_URL!)
  if (base.hostname.endsWith('.supabase.co')) {
    base.hostname = base.hostname.replace(/\.supabase\.co$/, '.storage.supabase.co')
  }
  base.pathname = '/storage/v1/upload/resumable'
  base.search = ''
  base.hash = ''
  return base.toString()
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
  void [documentId, newMatterId, mode]
  return { error: 'Document move and copy are unavailable until the governed workflow is ready.' }
}

// ── Dismiss Needs-Review Flag ─────────────────────────────────────

export async function dismissReviewFlag(documentId: string) {
  void documentId
  return { error: 'Legacy review dismissal is unavailable. Resolve typed Review items instead.' }
}

// ── Promote / Demote document class ──────────────────────────────

export async function setDocumentClass(
  documentId: string,
  newClass: 'proceeding' | 'supporting',
) {
  void [documentId, newClass]
  return { error: 'Document classification is unavailable until the governed impact workflow is ready.' }
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

/**
 * Resolve a version only after proving that it belongs to the exact canonical
 * document route the current user may read. This is the browser-facing source
 * locator boundary; the version-only signer above must remain reusable for
 * trusted server callers and is not sufficient for URL-supplied version IDs.
 */
export async function getCanonicalDocumentVersionSignedUrl(
  documentId: string,
  documentVersionId: string,
  expectedMatterId?: string,
) {
  const exactDocument = await getCanonicalAssignedDocument(documentId, expectedMatterId)
  if (!exactDocument) return { error: 'This document version is not available.' }

  const document = exactDocument.state === 'trash'
    ? exactDocument.data.record
    : exactDocument.record

  // This service lookup is deliberately limited to the stable relationship
  // identifier. It happens only after the authenticated canonical reader has
  // established the document route; it never reads or returns a storage path.
  const service = createServiceClient()
  const { data: version, error } = await service
    .from('document_versions')
    .select('id')
    .eq('id', documentVersionId)
    .eq('document_id', document.id)
    .maybeSingle()

  if (error || !version) return { error: 'This document version is not available.' }

  return exactDocument.state === 'trash'
    ? getTrashedDocumentVersionSignedUrl(exactDocument.expectedMatterId, documentId, documentVersionId)
    : getDocumentVersionSignedUrl(documentVersionId)
}

/**
 * Generate a short-lived PDF URL for one exact canonical Trash route. The
 * authenticated grant binds document, matter route, immutable version, active
 * Trash membership, and readable operation before the service client sees the
 * private Storage locator.
 */
export async function getTrashedDocumentVersionSignedUrl(
  matterId: string,
  documentId: string,
  documentVersionId: string,
) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { data: grants, error: grantError } = await supabase.rpc('get_trashed_document_version_read_grant', {
    p_document_id: documentId,
    p_expected_matter_id: matterId,
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
  if (error || !data) return { error: error?.message ?? 'Failed to generate view link.' }
  return { url: data.signedUrl }
}

/** Create an authorised short-lived PDF URL for a ready, unassigned intake. */
export async function getIntakeItemSignedUrl(intakeId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { data: grants, error: grantError } = await supabase.rpc('get_intake_item_read_grant', {
    p_intake_id: intakeId,
  })
  const grant = grants?.[0]
  if (grantError || !grant || grant.code !== 'ok' || !grant.bucket_id || !grant.object_key) {
    return { error: 'This intake PDF is not available for preview.' }
  }

  const storage = createServiceClient()
  const { data, error } = await storage.storage
    .from(grant.bucket_id)
    .createSignedUrl(grant.object_key, 60 * 15)
  if (error || !data) return { error: error?.message ?? 'Failed to generate view link.' }
  return { url: data.signedUrl }
}


export async function updateDocumentMetadata(docId: string, metadataKey: string, newValue: unknown) {
  void [docId, metadataKey, newValue]
  return { error: 'Legacy metadata editing is unavailable. Use the governed inspector correction workflow.' }
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
    .eq('record_state', 'active')
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
  revalidatePath(canonicalDocumentPath(fromDocId))
  revalidatePath(canonicalDocumentPath(toDocId))

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
  if (!link.to_doc_id) return { error: 'Pending links cannot be changed from this view.' }

  const { data: activeEndpoints } = await supabase
    .from('documents')
    .select('id')
    .in('id', [link.from_doc_id, link.to_doc_id])
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
  if ((activeEndpoints ?? []).length !== 2) return { error: 'Links are read-only while a document is in Trash.' }

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
  revalidatePath(canonicalDocumentPath(link.from_doc_id))
  revalidatePath(canonicalDocumentPath(link.to_doc_id))

  return { success: true }
}

export async function deleteDocument(documentId: string, idempotencyKey = `trash.document.${crypto.randomUUID()}`) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { data, error } = await supabase.rpc('trash_resource', {
    p_resource_type: 'document',
    p_resource_id: documentId,
    p_idempotency_key: idempotencyKey,
  })
  const result = data?.[0]

  if (error || !result) return { error: 'Could not move this document to Trash. Please try again.' }
  if (result.code === 'trashed' || result.code === 'already_trashed') {
    scheduleDocumentOutboxWake()
    revalidatePath('/matters')
    revalidatePath(canonicalDocumentPath(documentId))
    return { success: true, operationId: result.operation_id, status: result.code }
  }
  if (result.code === 'not_allowed') return { error: 'You do not have permission to move this document to Trash.' }
  if (result.code === 'not_available') return { error: 'This document is no longer available.' }
  if (result.code === 'idempotency_conflict') return { error: 'This request key was already used for another resource.' }
  return { error: 'Could not move this document to Trash. Please try again.' }
}
