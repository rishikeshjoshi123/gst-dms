'use server'

import { revalidatePath } from 'next/cache'

import { createClient } from '@/lib/supabase/server'
import { scheduleDocumentOutboxWake } from '@/lib/outbox/wake'
import { getCurrentOrgId } from './org'
import { canonicalInboxReason, canonicalInboxStatus } from '@/lib/inbox-compat'
import { normalizeInboxQueuePage, type InboxQueuePageOptions } from '@/lib/inbox-pagination'

export type InboxQueueDocument = {
  id: string
  source_kind: 'canonical_intake'
  storage_path: string
  status: string
  created_at: string
  intake_matter_id: string | null
  suggested_client: null
  suggested_matter: null
  suggested_matter_ids: null
  suggestion_reason: string | null
  raw_metadata: null
  canonical_intake_state: string
  canonical_failure_code: string | null
  is_mine: boolean
  uploaded_by: string
  uploaded_by_name: string
}

/** Canonical Inbox projection; legacy staged rows are retirement history. */
export type InboxQueueReadResult =
  | { ok: true; documents: InboxQueueDocument[]; total: number; offset: number; limit: number }
  | { ok: false; error: string }

type CanonicalIntakeRow = {
  id: string
  state: string
  failure_code: string | null
  created_at: string
  intended_matter_id: string | null
  declared_filename: string
  is_mine: boolean
  uploaded_by: string
  uploaded_by_name: string
  total_count: number
}

function projectInboxDocument(item: CanonicalIntakeRow): InboxQueueDocument {
  return {
    id: item.id,
    source_kind: 'canonical_intake',
    storage_path: item.declared_filename || 'Untitled PDF',
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
    is_mine: item.is_mine,
    uploaded_by: item.uploaded_by,
    uploaded_by_name: item.uploaded_by_name,
  }
}

export async function getStagedDocuments(options: InboxQueuePageOptions = {}): Promise<InboxQueueReadResult> {
  const orgId = await getCurrentOrgId()
  if (!orgId) return { ok: false, error: 'No active organisation is available.' }
  const { offset, limit, includeId, ownershipScope } = normalizeInboxQueuePage(options)
  const supabase = await createClient()
  const { data: intakeItems, error } = await supabase.rpc('get_document_hub_intake', {
    p_scope: ownershipScope,
    p_offset: offset,
    p_limit: limit,
    p_include_id: includeId,
  })

  if (error) {
    console.error('Failed to load canonical inbox intakes:', error)
    return { ok: false, error: 'The document queue could not be loaded.' }
  }
  const rows = (intakeItems ?? []) as CanonicalIntakeRow[]

  return {
    ok: true,
    documents: rows.map(projectInboxDocument),
    total: rows[0]?.total_count ?? 0,
    offset,
    limit,
  }
}

export async function getStagedDocumentCount() {
  const result = await getStagedDocuments({ ownershipScope: 'all', limit: 1 })
  return result.ok ? result.total : 0
}

export async function assignCanonicalIntakeToMatter(intakeId: string, matterId: string, idempotencyKey: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { data: contexts, error: contextError } = await supabase.rpc('get_intake_item_triage_context', {
    p_intake_id: intakeId,
  })
  const intake = contexts?.[0]
  if (contextError || !intake || intake.code !== 'ok' || !intake.uploaded_by) {
    return { error: 'This intake is no longer ready for placement.' }
  }

  const displayTitle = intake.declared_filename
    ?.replace(/[\u0000-\u001F\u007F]/g, '')
    .replace(/\.pdf$/i, '')
    .trim() || 'Uploaded document'
  const { data, error } = await supabase.rpc('assign_intake_to_new_document', {
    p_intake_id: intakeId,
    p_matter_id: matterId,
    p_display_title: displayTitle.slice(0, 255),
    p_expected_intake_uploader: intake.uploaded_by,
    p_idempotency: idempotencyKey,
  })
  const result = data?.[0]
  if (result?.code === 'duplicate_reference') {
    return { error: 'This PDF is already referenced by an existing record. Refresh the Inbox to review the duplicate.' }
  }
  if (error || !result || result.code !== 'ok') {
    return { error: error?.message ?? 'This intake could not be assigned. Refresh the queue and try again.' }
  }

  // The command committed durable work before this fixed best-effort wake;
  // browser assignment data never reaches Trigger.
  scheduleDocumentOutboxWake()
  revalidatePath('/documents')
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

  revalidatePath('/documents')
  revalidatePath('/', 'layout')
  return { success: true as const }
}

export async function getCanonicalDuplicateResolution(intakeId: string) {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_intake_duplicate_resolution', { p_intake_id: intakeId })
  const result = data?.[0]
  if (error || !result) return { code: 'not_available' as const }
  if (result.code === 'in_trash') return { code: 'in_trash' as const }
  if (result.code === 'restricted') return { code: 'restricted' as const }
  if (result.code === 'intake' && result.intake_id) {
    return { code: 'intake' as const, intakeId: result.intake_id }
  }
  if (result.code === 'ok' && result.document_id && result.matter_id) {
    return { code: 'ok' as const, documentId: result.document_id, matterId: result.matter_id }
  }
  return { code: 'not_available' as const }
}
