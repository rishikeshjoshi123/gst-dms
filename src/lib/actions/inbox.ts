'use server'

import { revalidatePath } from 'next/cache'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { scheduleDocumentOutboxWake } from '@/lib/outbox/wake'
import { uploadToDocumentIntake } from './document'
import { getCurrentOrgId } from './org'
import { canonicalInboxReason, canonicalInboxStatus } from '@/lib/inbox-compat'

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
}

/** Canonical Inbox projection; legacy staged rows are retirement history. */
export async function getStagedDocuments(): Promise<InboxQueueDocument[]> {
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  // Lifecycle tables intentionally have no browser table grant. The server
  // resolves the active organisation and returns only canonical Intake rows.
  const service = createServiceClient()
  const { data: intakeItems, error } = await service
    .from('intake_items')
    .select('id, state, failure_code, created_at, intended_matter_id, upload_session:upload_sessions(declared_filename)')
    .eq('org_id', orgId)
    .in('state', ['awaiting_upload', 'uploaded', 'validating', 'processing', 'ready', 'duplicate', 'failed'])
    .order('created_at', { ascending: true })

  if (error) {
    console.error('Failed to load canonical inbox intakes:', error)
    return []
  }

  return (intakeItems ?? []).map((item) => {
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
}

export async function getStagedDocumentCount() {
  return (await getStagedDocuments()).length
}

export async function uploadToInbox(formData: FormData) {
  // Matter context is only canonical Intake context; it never creates a
  // staging-bucket object or staged_documents row.
  const matterId = formData.get('matterId')
  const intendedMatterId = typeof matterId === 'string' && matterId.length > 0 ? matterId : null
  const result = await uploadToDocumentIntake(formData, intendedMatterId)
  if ('success' in result) revalidatePath('/', 'layout')
  return result
}

export async function assignCanonicalIntakeToMatter(intakeId: string, matterId: string, idempotencyKey: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

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
  if (result?.code === 'duplicate_reference') {
    return { error: 'This PDF is already referenced by an existing record. Refresh the Inbox to review the duplicate.' }
  }
  if (error || !result || result.code !== 'ok') {
    return { error: error?.message ?? 'This intake could not be assigned. Refresh the queue and try again.' }
  }

  // The command committed durable work before this fixed best-effort wake;
  // browser assignment data never reaches Trigger.
  scheduleDocumentOutboxWake()
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
