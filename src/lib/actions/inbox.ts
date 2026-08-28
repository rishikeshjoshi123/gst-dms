'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'
import { after } from 'next/server'
import { tasks } from '@trigger.dev/sdk/v3'
import type { AIDocumentResult } from '@/lib/ai/vertex'
import { uploadToDocumentIntake } from './document'
import { canonicalInboxReason, canonicalInboxStatus } from '@/lib/inbox-compat'

async function getLegacyStagedDocumentActionGuard(orgId: string, stagedId: string) {
  const service = createServiceClient()
  const { data, error } = await (service as any).rpc('get_staged_document_backfill_action_guard', {
    p_org_id: orgId,
    p_legacy_staged_document_id: stagedId,
  })
  const code = data?.[0]?.code as string | undefined
  return error || !code ? 'unavailable' : code
}

type LegacyActionKind = 'assign' | 'discard' | 'analyze'

async function reserveLegacyStagedDocumentAction(orgId: string, stagedId: string, actionKind: LegacyActionKind) {
  const service = createServiceClient()
  const { data, error } = await (service as any).rpc('reserve_legacy_staged_document_action', {
    p_org_id: orgId,
    p_legacy_staged_document_id: stagedId,
    p_action_kind: actionKind,
  })
  const reservation = data?.[0]
  if (error || reservation?.code !== 'ok' || !reservation.lease_token) {
    return { error: legacyStagedDocumentFenceError(reservation?.code ?? 'unavailable') } as const
  }
  return { service, leaseToken: reservation.lease_token as string } as const
}

async function releaseLegacyStagedDocumentAction(orgId: string, stagedId: string, leaseToken: string) {
  const service = createServiceClient()
  await (service as any).rpc('release_legacy_staged_document_action', {
    p_org_id: orgId,
    p_legacy_staged_document_id: stagedId,
    p_lease_token: leaseToken,
  })
}

async function getLegacyStagedDocumentActionSource(
  service: ReturnType<typeof createServiceClient>, orgId: string, stagedId: string, leaseToken: string, actionKind: LegacyActionKind,
) {
  const { data, error } = await (service as any).rpc('get_legacy_staged_document_action_source_grant', {
    p_org_id: orgId,
    p_legacy_staged_document_id: stagedId,
    p_lease_token: leaseToken,
    p_action_kind: actionKind,
  })
  const grant = data?.[0]
  return !error && grant?.code === 'ok' && grant.bucket_id && grant.object_key ? grant : null
}

async function getLegacyStagedEligibleIds(orgId: string) {
  const service = createServiceClient()
  const { data, error } = await (service as any).rpc('get_legacy_staged_document_eligible_ids', { p_org_id: orgId })
  if (error) return null
  return (data ?? []).map((row: { legacy_staged_document_id: string }) => row.legacy_staged_document_id)
}

function legacyStagedDocumentFenceError(code: string) {
  if (code === 'backfill_fenced') {
    return 'This legacy intake is being preserved by the migration and cannot be changed from the legacy workflow.'
  }
  return 'This legacy intake is no longer available. Refresh the queue and try again.'
}

// ── Transitional Inbox projection ─────────────────────────────────

export type InboxQueueDocument = {
  id: string
  source_kind: 'canonical_intake' | 'legacy_staged_document'
  storage_path: string
  status: string
  created_at: string
  intake_matter_id: string | null
  suggested_client: unknown | null
  suggested_matter: unknown | null
  suggested_matter_ids: string[] | null
  suggestion_reason: string | null
  raw_metadata: unknown
  canonical_intake_state?: string
  canonical_failure_code?: string | null
}

/**
 * Transitional Inbox projection. New rows come exclusively from canonical
 * intake_items; staged_documents are read-only compatibility records until
 * the following assignment/backfill tranche removes this adapter.
 */
export async function getStagedDocuments(): Promise<InboxQueueDocument[]> {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  // Lifecycle tables intentionally have no authenticated table grant. The
  // server has already resolved the active organisation from the user's
  // session, so this narrowly-scoped service read is the compatibility
  // projection rather than a new client data-access surface.
  const service = createServiceClient()
  const { data: fenceRows, error: fenceError } = await (service as any)
    .rpc('get_staged_document_backfill_adapter_fences', { p_org_id: orgId })
  const fencedLegacyIds = new Set(
    (fenceRows ?? []).map((row: { legacy_staged_document_id: string }) => row.legacy_staged_document_id),
  )
  if (fenceError) {
    // Failing closed keeps a mapped row out of the legacy action surface when
    // the service-only fence cannot be resolved.
    console.error('Failed to resolve staged-document backfill fences:', fenceError)
  }
  const eligibleLegacyIds = fenceError ? [] : (await getLegacyStagedEligibleIds(orgId))
  // Resolve eligibility before the compatibility projection reads raw legacy
  // metadata. A mapped or action-reserved row never enters this surface.
  const { data, error } = eligibleLegacyIds && eligibleLegacyIds.length > 0
    ? await supabase
      .from('staged_documents')
      .select(`
        *,
        suggested_client:clients(id, name, gstin),
        suggested_matter:matters!staged_documents_suggested_matter_id_fkey(id, title, financial_year, matter_code)
      `)
      .eq('org_id', orgId)
      .in('id', eligibleLegacyIds)
      .in('status', ['pending_assignment', 'analyzing', 'ready_to_assign', 'failed'])
      .order('created_at', { ascending: true })
    : { data: [] as any[], error: null }
  if (error) console.error('Failed to load staged documents:', error)
  const legacyItems: InboxQueueDocument[] = fenceError ? [] : (data ?? [])
    .filter((document) => !fencedLegacyIds.has(document.id))
    .map((document) => ({
      ...(document as unknown as InboxQueueDocument),
      source_kind: 'legacy_staged_document' as const,
    }))

  const { data: intakeItems, error: intakeError } = await service
    .from('intake_items')
    .select('id, state, failure_code, created_at, intended_matter_id, upload_session:upload_sessions(declared_filename)')
    .eq('org_id', orgId)
    .in('state', ['awaiting_upload', 'uploaded', 'validating', 'processing', 'ready', 'duplicate', 'failed'])
    .order('created_at', { ascending: true })

  if (intakeError) {
    console.error('Failed to load canonical inbox intakes:', intakeError)
    return legacyItems
  }

  const canonicalItems: InboxQueueDocument[] = (intakeItems ?? []).map((item) => {
    const session = item.upload_session as unknown as { declared_filename: string } | null
    return {
    id: item.id,
    source_kind: 'canonical_intake' as const,
    storage_path: session?.declared_filename ?? 'Untitled PDF',
    status: canonicalInboxStatus(item.state),
    created_at: item.created_at,
    intake_matter_id: item.intended_matter_id,
    suggested_client: null,
    suggested_matter: null,
    suggested_matter_ids: null,
    suggestion_reason: canonicalInboxReason(item.state, item.failure_code),
    raw_metadata: null,
    canonical_intake_state: item.state,
    canonical_failure_code: item.failure_code,
    }
  })

  return [...canonicalItems, ...legacyItems]
}

export async function getStagedDocumentCount() {
  return (await getStagedDocuments()).length
}

// ── Canonical global upload ───────────────────────────────────────

export async function uploadToInbox(formData: FormData) {
  // The optional Inbox matter context is declared intake context only. It is
  // validated by the canonical reservation command; it never creates a staged
  // row or a staging-bucket object.
  const matterId = formData.get('matterId')
  const intendedMatterId = typeof matterId === 'string' && matterId.length > 0 ? matterId : null
  const result = await uploadToDocumentIntake(formData, intendedMatterId)
  if ('success' in result) revalidatePath('/', 'layout')
  return result
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

  // Verify matter belongs to this org
  const { data: matter } = await supabase
    .from('matters')
    .select('id, org_id')
    .eq('id', matterId)
    .eq('org_id', orgId)
    .single()

  if (!matter) return { error: 'Matter not found.' }

  // This reservation locks the legacy row and prevents a backfill map from
  // being created until every legacy Storage side effect has finished.
  const reservation = await reserveLegacyStagedDocumentAction(orgId, stagedId, 'assign')
  if ('error' in reservation) return reservation
  const { service, leaseToken } = reservation
  try {
    const sourceGrant = await getLegacyStagedDocumentActionSource(service, orgId, stagedId, leaseToken, 'assign')
    if (!sourceGrant) return { error: 'This legacy intake is no longer available. Refresh the queue and try again.' }

    // Read metadata only after the database reservation. Storage paths always
    // come from the grant, never from this legacy row or a browser payload.
    const { data: staged } = await supabase
      .from('staged_documents')
      .select('id, status, raw_metadata')
      .eq('id', stagedId)
      .eq('org_id', orgId)
      .single()
    if (!staged) return { error: 'Staged document not found.' }
    if (staged.status === 'manually_assigned' || staged.status === 'auto_assigned') return { error: 'Document already assigned.' }

  // 1. Copy file from the server-issued staging grant to 'documents'.
  const baseName = sourceGrant.object_key.split('/').pop() || 'document.pdf'
  const newPath = `${orgId}/${matterId}/${Date.now()}_${baseName}`

  const { data: fileData, error: downloadError } = await service.storage
    .from(sourceGrant.bucket_id)
    .download(sourceGrant.object_key)

  if (downloadError || !fileData) {
    console.error('Failed to download from staging:', downloadError)
    return { error: 'Failed to access document file in staging storage.' }
  }

  const { error: uploadError } = await service.storage
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
    await service.storage.from('documents').remove([newPath])
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

  // 4. Re-read the grant immediately before deleting Storage. The active
  // reservation makes this check and the later source update mutually
  // exclusive with mapping; never remove a source on a stale app-only guard.
  const deleteGrant = await getLegacyStagedDocumentActionSource(service, orgId, stagedId, leaseToken, 'assign')
  if (!deleteGrant) return { error: 'The document was copied but its legacy source could not be safely retired. Please contact support.' }
  const { error: removeError } = await service.storage.from(deleteGrant.bucket_id).remove([deleteGrant.object_key])
  if (removeError) return { error: 'The document was copied but the legacy source could not be removed. Please retry later.' }
  await supabase
    .from('staged_documents')
    .update({ status: 'manually_assigned' })
    .eq('id', stagedId)

  revalidatePath('/inbox')
  revalidatePath('/', 'layout')
  revalidatePath(`/matters/${matterId}`)
  return { success: true, documentId: doc.id }
  } finally {
    await releaseLegacyStagedDocumentAction(orgId, stagedId, leaseToken)
  }
}

// ── Canonical Intake placement and discard ───────────────────────

export async function assignCanonicalIntakeToMatter(intakeId: string, matterId: string, idempotencyKey: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  // The trusted filename lives on the upload session. The browser never
  // chooses a storage path, asset, or source file for materialisation.
  const service = createServiceClient()
  const { data: intake, error: intakeError } = await service
    .from('intake_items')
    .select('id, org_id, state, upload_session:upload_sessions(declared_filename)')
    .eq('id', intakeId)
    .eq('org_id', orgId)
    .single()
  if (intakeError || !intake || intake.state !== 'ready') return { error: 'This intake is no longer ready for placement.' }

  const session = intake.upload_session as unknown as { declared_filename: string } | null
  const displayTitle = session?.declared_filename
    ?.replace(/[\u0000-\u001F\u007F]/g, '')
    .replace(/\.pdf$/i, '')
    .trim() || 'Uploaded document'
  const { data, error } = await supabase.rpc('assign_intake_to_new_document', {
    p_intake_id: intakeId,
    p_matter_id: matterId,
    p_display_title: displayTitle.slice(0, 255),
    p_expected_intake_uploader: user.id,
    p_idempotency: idempotencyKey,
  })
  const result = data?.[0]
  if (error || !result || result.code !== 'ok') {
    return { error: error?.message ?? 'This intake could not be assigned. Refresh the queue and try again.' }
  }

  revalidatePath('/inbox')
  revalidatePath('/', 'layout')
  revalidatePath(`/matters/${matterId}`)
  return { success: true as const, documentId: result.document_id }
}

export async function discardCanonicalIntake(intakeId: string, idempotencyKey: string) {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('discard_intake_item', {
    p_intake_id: intakeId,
    p_idempotency: idempotencyKey,
  })
  const result = data?.[0]
  if (error || !result || !['ok', 'already_discarded'].includes(result.code)) {
    return { error: error?.message ?? 'This intake could not be discarded. Refresh the queue and try again.' }
  }

  revalidatePath('/inbox')
  revalidatePath('/', 'layout')
  return { success: true as const }
}

export async function getCanonicalDuplicateResolution(intakeId: string) {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_intake_duplicate_resolution', { p_intake_id: intakeId })
  const result = data?.[0]
  if (error || !result) {
    return { code: 'not_available' as const }
  }
  if (result.code === 'in_trash') return { code: 'in_trash' as const }
  if (result.code === 'ok' && result.document_id && result.matter_id) {
    return { code: 'ok' as const, documentId: result.document_id, matterId: result.matter_id }
  }
  return { code: 'not_available' as const }
}

// ── Auto-Create Client & Matter for Staged Document ──────────────────

export async function autoCreateClientAndMatterForStagedDocument(stagedId: string, selectedFy?: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const backfillGuard = await getLegacyStagedDocumentActionGuard(orgId, stagedId)
  if (backfillGuard !== 'ok') return { error: legacyStagedDocumentFenceError(backfillGuard) }

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

  const reservation = await reserveLegacyStagedDocumentAction(orgId, stagedId, 'discard')
  if ('error' in reservation) return reservation
  const { service: db, leaseToken } = reservation
  try {
    // This grant is the final database confirmation before the irreversible
    // Storage remove. It also binds the operation to this organisation/source.
    const sourceGrant = await getLegacyStagedDocumentActionSource(db, orgId, stagedId, leaseToken, 'discard')
    if (!sourceGrant) return { error: 'This legacy intake is no longer available. Refresh the queue and try again.' }
    const { error: storageError } = await db.storage.from(sourceGrant.bucket_id).remove([sourceGrant.object_key])
    if (storageError) return { error: 'Failed to remove the staged document file. The intake was left unchanged.' }

    const { error } = await db
    .from('staged_documents')
    .delete()
    .eq('id', stagedId)
    .eq('org_id', orgId)

    if (error) {
      console.error('Discard staged error:', error)
      return { error: error.message }
    }

    revalidatePath('/inbox')
    revalidatePath('/', 'layout')
    return { success: true }
  } finally {
    await releaseLegacyStagedDocumentAction(orgId, stagedId, leaseToken)
  }
}

export const discardStagedDocument = deleteStagedDocument


// ── Re-evaluate Staged Documents ─────────────────────────────────────────

export async function reevaluateStagedDocuments() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return

  const eligibleIds = await getLegacyStagedEligibleIds(orgId)
  if (!eligibleIds || eligibleIds.length === 0) return
  const { data: staged } = await supabase
    .from('staged_documents')
    .select('*')
    .eq('org_id', orgId)
    .eq('status', 'ready_to_assign')
    .in('id', eligibleIds)

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

  const eligibleIds = await getLegacyStagedEligibleIds(orgId)
  if (!eligibleIds || eligibleIds.length === 0) return

  const { data: staged } = await supabase
    .from('staged_documents')
    .select('*')
    .eq('org_id', orgId)
    .eq('status', 'ready_to_assign')
    .in('id', eligibleIds)

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
