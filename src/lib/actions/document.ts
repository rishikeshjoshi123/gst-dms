'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'
import { redirect, RedirectType } from 'next/navigation'
import type { Database } from '@/lib/supabase/database.types'
import { appendActivity } from '@/lib/activity'
import { scheduleDocumentOutboxWake } from '@/lib/outbox/wake'
import {
  observeStoredPdf,
  ownsTerminalUploadCleanup,
  uploadFailureResult,
  uploadIdempotencyKey,
} from '@/lib/document-upload'
import { buildMatterReturnPath, canonicalDocumentPath } from '@/lib/canonical-document-route'
import { getCanonicalAssignedDocument } from '@/lib/trash/exact-resource'
import { pdfSourceLookupFailureCode } from '@/lib/pdf-source-access'
import { z } from 'zod'

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

type DocumentUploadCancelInput = DocumentUploadFinalizationInput

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

  if (sessionError || !session) {
    return uploadFailureResult('This upload reservation is no longer available.', 'terminal')
  }

  if (session.state !== 'reserved') {
    const { data: receipts, error: receiptError } = await storage.rpc('get_document_upload_completion_receipt', {
      p_session: uploadSessionId,
      p_idempotency: idempotencyKey,
      p_actor: user.id,
      p_org: orgId,
    })
    const receipt = receipts?.[0]
    if (receiptError || !receipt || receipt.code === 'not_found') {
      return uploadFailureResult('This upload reservation is no longer available.', 'terminal')
    }
    if (receipt.code === 'duplicate') return uploadFailureResult(documentUploadError('duplicate'), 'duplicate')
    if (receipt.code === 'ok' && receipt.intake_item_id) {
      scheduleDocumentOutboxWake()
      revalidatePath('/documents')
      revalidatePath('/', 'layout')
      return { success: true as const, intakeId: receipt.intake_item_id }
    }
    return uploadFailureResult('This upload reservation is no longer available.', 'terminal')
  }
  if (new Date(session.expires_at).getTime() <= Date.now()) {
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
    p_actor: user.id,
    p_org: orgId,
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
      return uploadFailureResult(documentUploadError(completion.code), 'duplicate')
    } else if (completion.code === 'cancelled') {
      return { cancelled: true as const, cleanupPending: true as const }
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

/** Serialise cancellation with finalisation; cleanup waits for token expiry. */
export async function cancelDocumentUpload(input: DocumentUploadCancelInput) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return uploadFailureResult('No active organisation.', 'terminal')
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return uploadFailureResult('Not authenticated.', 'terminal')

  const idempotencyKey = uploadIdempotencyKey(input.idempotencyKey)
  const uploadSessionId = uploadIdempotencyKey(input.uploadSessionId)
  if (!idempotencyKey || !uploadSessionId) return uploadFailureResult('This upload could not be cancelled safely.', 'terminal')

  const storage = createServiceClient()
  const { data: session, error: sessionError } = await storage
    .from('upload_sessions')
    .select('id, asset_id')
    .eq('id', uploadSessionId)
    .eq('org_id', orgId)
    .eq('created_by', user.id)
    .eq('idempotency_key', idempotencyKey)
    .maybeSingle()
  if (sessionError || !session) return uploadFailureResult('This upload reservation is no longer available.', 'terminal')

  const { data: outcomes, error: cancelError } = await storage.rpc('cancel_document_upload', {
    p_session: uploadSessionId,
    p_idempotency: idempotencyKey,
    p_actor: user.id,
    p_org: orgId,
  })
  const outcome = outcomes?.[0]
  if (cancelError || !outcome) return uploadFailureResult('The upload could not be cancelled. Please try again.')
  if (outcome.code === 'already_completed') {
    if (outcome.completion_code === 'ok' && outcome.intake_item_id) {
      scheduleDocumentOutboxWake()
      return { success: true as const, intakeId: outcome.intake_item_id, cancelLostRace: true as const }
    }
    if (outcome.completion_code === 'duplicate') return uploadFailureResult(documentUploadError('duplicate'), 'duplicate')
    return uploadFailureResult('This upload reservation is no longer available.', 'terminal')
  }
  if (outcome.code !== 'cancelled' || !outcome.asset_id) {
    return uploadFailureResult('This upload reservation is no longer available.', 'terminal')
  }

  // A token minted near session expiry remains valid beyond the reservation.
  // Keep worst-case bytes charged and let the scheduled cleaner delete and
  // tombstone only after the migration's full authorization horizon.
  return { cancelled: true as const, cleanupPending: true as const }
}

function resumableStorageEndpoint() {
  const base = new URL(process.env.NEXT_PUBLIC_SUPABASE_URL!)
  if (base.hostname.endsWith('.supabase.co')) {
    base.hostname = base.hostname.replace(/\.supabase\.co$/, '.storage.supabase.co')
  }
  // Signed upload tokens are verified only by Storage's signed TUS route.
  // The authenticated route treats the request as an ordinary RLS upload.
  base.pathname = '/storage/v1/upload/resumable/sign'
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
  mode: 'move' | 'copy' = 'move',
  confirmation?: { fingerprint: string; reason: string; idempotencyKey: string; sourceVersionId?: string; sourcePage?: number }
) {
  const request = z.object({
    documentId: z.string().uuid(), newMatterId: z.string().uuid(), mode: z.enum(['move', 'copy']),
    confirmation: z.object({ fingerprint: z.string().regex(/^[a-f0-9]{64}$/),
      reason: z.string().trim().min(1).max(500).regex(/^[^\x00-\x1f\x7f]*$/), idempotencyKey: z.string().uuid(),
      sourceVersionId: z.string().uuid().optional(), sourcePage: z.number().int().positive().safe().optional() }),
  }).safeParse({ documentId, newMatterId, mode, confirmation })
  if (!request.success) return { error: 'Review the impact and enter a reason before confirming.' }
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('execute_document_boundary_repair', {
    p_document_id: documentId, p_target_matter_id: newMatterId, p_mode: mode,
    p_expected_fingerprint: request.data.confirmation.fingerprint,
    p_reason: request.data.confirmation.reason, p_idempotency_key: request.data.confirmation.idempotencyKey,
  })
  const result = z.object({ code: z.string(), documentId: z.string().uuid().optional(),
    sourceMatterId: z.string().uuid().optional(), targetMatterId: z.string().uuid().optional() }).safeParse(data)
  if (error || !result.success) return { error: 'Could not confirm the change. Retry with the same confirmation.' }
  if (result.data.code !== 'ok') return { error: boundaryRepairError(result.data.code), code: result.data.code }
  if (!result.data.documentId || !result.data.sourceMatterId || !result.data.targetMatterId) return { error: 'The change could not be verified. Refresh the document.' }
  scheduleDocumentOutboxWake()
  revalidatePath(canonicalDocumentPath(documentId))
  revalidatePath(canonicalDocumentPath(result.data.documentId))
  revalidatePath(`/matters/${result.data.sourceMatterId}`)
  revalidatePath(`/matters/${result.data.targetMatterId}`)
  revalidatePath('/documents')
  revalidatePath('/tasks')
  revalidatePath('/notes')
  revalidatePath('/matters')
  revalidatePath('/clients')
  revalidatePath('/dashboard')
  revalidatePath('/search')
  if (mode === 'move') {
    // Redirect in the same action response: refreshing the old Matter-scoped
    // URL first would render notFound before a client callback could navigate.
    const destination = canonicalDocumentPath(result.data.documentId, {
      matterId: result.data.targetMatterId,
      returnTo: buildMatterReturnPath(result.data.targetMatterId, []),
      ...(request.data.confirmation.sourceVersionId && {
        version: request.data.confirmation.sourceVersionId,
        page: String(request.data.confirmation.sourcePage ?? 1),
      }),
    })
    redirect(`${destination}#document-workbench`, RedirectType.replace)
  }
  return { success: true, documentId: result.data.documentId }
}

const boundaryImpactSchema = z.object({
  code: z.literal('ok'), documentId: z.string().uuid(), documentTitle: z.string(),
  sourceMatterId: z.string().uuid(), sourceMatterTitle: z.string(),
  targetMatterId: z.string().uuid(), targetMatterTitle: z.string(), mode: z.enum(['move', 'copy']),
  documentRevision: z.number().int().positive(), sourceRevision: z.number().int().positive(), targetRevision: z.number().int().positive(),
  versionId: z.string().uuid(), sharedAssets: z.literal(1), fingerprint: z.string().regex(/^[a-f0-9]{64}$/),
  categories: z.array(z.object({ key: z.string(), label: z.string(), count: z.number().int().nonnegative() })).max(30),
  blockers: z.array(z.string()).max(30),
})
export type BoundaryRepairImpact = z.infer<typeof boundaryImpactSchema>

function boundaryRepairError(code: string) {
  if (code === 'stale_preview') return 'The document or its consequences changed. Review a fresh impact preview.'
  if (code === 'busy') return 'Another change is in progress. Please retry.'
  if (code === 'blocked') return 'Resolve the blockers shown in the impact preview first.'
  if (code === 'source_unavailable') return 'A current, validated PDF is required for this repair.'
  if (code === 'impact_too_large') return 'This document has too many dependencies for a one-document repair.'
  if (code === 'idempotency_conflict') return 'This confirmation has changed. Review the impact again.'
  if (code === 'not_allowed') return 'Only an active Owner, Admin or Associate can move or copy a document.'
  if (code === 'context_unavailable') return 'Choose a different active Matter. Closed or trashed records cannot be repaired here.'
  return 'The change was not completed. Review the impact and try again.'
}

export async function previewDocumentBoundaryRepair(documentId: string, newMatterId: string, mode: 'move' | 'copy') {
  if (!z.string().uuid().safeParse(documentId).success || !z.string().uuid().safeParse(newMatterId).success || !['move', 'copy'].includes(mode)) return { error: 'Choose a document and target Matter.' }
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('preview_document_boundary_repair', {
    p_document_id: documentId, p_target_matter_id: newMatterId, p_mode: mode,
  })
  if (error) return { error: 'Could not load the impact. Please retry.' }
  const impact = boundaryImpactSchema.safeParse(data)
  if (impact.success) return { impact: impact.data }
  const result = z.object({ code: z.string() }).safeParse(data)
  return { error: boundaryRepairError(result.success ? result.data.code : 'unavailable') }
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
  if (!user) return { error: 'Not authenticated.', code: 'not_authenticated' as const }

  const { data: grants, error: grantError } = await supabase.rpc('get_document_version_read_grant', {
    p_document_version_id: documentVersionId,
  })
  const grant = grants?.[0]
  const bucketId = grant?.bucket_id
  const objectKey = grant?.object_key
  const grantFailureCode = pdfSourceLookupFailureCode({
    lookupFailed: Boolean(grantError),
    sourceAvailable: Boolean(grant?.code === 'ok' && bucketId && objectKey),
  })
  if (grantFailureCode) {
    if (grantError) console.error('Failed to resolve versioned document read grant:', grantError)
    return grantFailureCode === 'access_temporary'
      ? { error: 'PDF source access is temporarily unavailable.', code: grantFailureCode }
      : { error: 'This document version is not available.', code: grantFailureCode }
  }
  if (!bucketId || !objectKey) return { error: 'This document version is not available.', code: 'source_unavailable' as const }

  const storage = createServiceClient()
  const { data, error } = await storage.storage
    .from(bucketId)
    .createSignedUrl(objectKey, 60 * 15)

  if (error || !data) {
    console.error('Failed to create versioned document URL:', error)
    return { error: 'PDF source access is temporarily unavailable.', code: 'access_temporary' as const }
  }

  return { url: data.signedUrl, code: 'ok' as const }
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
  requestedPage?: number,
) {
  const exactDocument = await getCanonicalAssignedDocument(documentId, expectedMatterId)
  if (!exactDocument) return { error: 'This document version is not available.', code: 'source_unavailable' as const }

  const document = exactDocument.state === 'trash'
    ? exactDocument.data.record
    : exactDocument.record

  // This service lookup is deliberately limited to the stable relationship
  // identifier. It happens only after the authenticated canonical reader has
  // established the document route; it never reads or returns a storage path.
  const service = createServiceClient()
  const { data: version, error } = await service
    .from('document_versions')
    .select('id, version_number, page_count, state, validation_state')
    .eq('id', documentVersionId)
    .eq('document_id', document.id)
    .in('state', ['current', 'superseded'])
    .eq('validation_state', 'valid')
    .maybeSingle()

  const versionFailureCode = pdfSourceLookupFailureCode({
    lookupFailed: Boolean(error),
    sourceAvailable: Boolean(version),
  })
  if (versionFailureCode) {
    if (error) console.error('Failed to resolve canonical document version:', error)
    return versionFailureCode === 'access_temporary'
      ? { error: 'PDF source access is temporarily unavailable.', code: versionFailureCode }
      : { error: 'This document version is not available.', code: versionFailureCode }
  }
  if (!version) return { error: 'This document version is not available.', code: 'source_unavailable' as const }

  if (!version.page_count || (requestedPage !== undefined && requestedPage > version.page_count)) {
    return { error: 'This document source location is not available.', code: 'source_unavailable' as const }
  }

  const signedSource = await (exactDocument.state === 'trash'
    ? getTrashedDocumentVersionSignedUrl(exactDocument.expectedMatterId, documentId, documentVersionId)
    : getDocumentVersionSignedUrl(documentVersionId))

  return {
    ...signedSource,
    versionId: version.id,
    versionNumber: version.version_number,
    pageCount: version.page_count,
    isCurrent: document.current_version_id === version.id,
  }
}

/** Renew one client-held canonical source without ever resolving to latest. */
export async function renewCanonicalDocumentVersionSource(input: {
  documentId: string
  documentVersionId: string
  expectedMatterId?: string
  page: number
}) {
  const result = await getCanonicalDocumentVersionSignedUrl(
    input.documentId,
    input.documentVersionId,
    input.expectedMatterId,
    input.page,
  )
  return result.code === 'ok' && 'url' in result ? result.url : null
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
  if (!user) return { error: 'Not authenticated.', code: 'not_authenticated' as const }

  const { data: grants, error: grantError } = await supabase.rpc('get_trashed_document_version_read_grant', {
    p_document_id: documentId,
    p_expected_matter_id: matterId,
    p_document_version_id: documentVersionId,
  })
  const grant = grants?.[0]
  const bucketId = grant?.bucket_id
  const objectKey = grant?.object_key
  const grantFailureCode = pdfSourceLookupFailureCode({
    lookupFailed: Boolean(grantError),
    sourceAvailable: Boolean(grant?.code === 'ok' && bucketId && objectKey),
  })
  if (grantFailureCode) {
    if (grantError) console.error('Failed to resolve trashed document read grant:', grantError)
    return grantFailureCode === 'access_temporary'
      ? { error: 'PDF source access is temporarily unavailable.', code: grantFailureCode }
      : { error: 'This document version is not available.', code: grantFailureCode }
  }
  if (!bucketId || !objectKey) return { error: 'This document version is not available.', code: 'source_unavailable' as const }

  const storage = createServiceClient()
  const { data, error } = await storage.storage
    .from(bucketId)
    .createSignedUrl(objectKey, 60 * 15)
  if (error || !data) {
    console.error('Failed to create trashed document URL:', error)
    return { error: 'PDF source access is temporarily unavailable.', code: 'access_temporary' as const }
  }
  return { url: data.signedUrl, code: 'ok' as const }
}

/** Create an authorised short-lived PDF URL for a ready, unassigned intake. */
export async function getIntakeItemSignedUrl(intakeId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.', code: 'not_authenticated' as const }

  const { data: grants, error: grantError } = await supabase.rpc('get_intake_item_read_grant', {
    p_intake_id: intakeId,
  })
  const grant = grants?.[0]
  const bucketId = grant?.bucket_id
  const objectKey = grant?.object_key
  const grantFailureCode = pdfSourceLookupFailureCode({
    lookupFailed: Boolean(grantError),
    sourceAvailable: Boolean(grant?.code === 'ok' && bucketId && objectKey),
  })
  if (grantFailureCode) {
    if (grantError) console.error('Failed to resolve intake document read grant:', grantError)
    return grantFailureCode === 'access_temporary'
      ? { error: 'PDF source access is temporarily unavailable.', code: grantFailureCode }
      : { error: 'This intake PDF is not available for preview.', code: grantFailureCode }
  }
  if (!bucketId || !objectKey) return { error: 'This intake PDF is not available for preview.', code: 'source_unavailable' as const }

  const storage = createServiceClient()
  const { data, error } = await storage.storage
    .from(bucketId)
    .createSignedUrl(objectKey, 60 * 15)
  if (error || !data) {
    console.error('Failed to create intake document URL:', error)
    return { error: 'PDF source access is temporarily unavailable.', code: 'access_temporary' as const }
  }
  return { url: data.signedUrl, code: 'ok' as const }
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
