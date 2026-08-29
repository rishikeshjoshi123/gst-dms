'use server'

import { createClient } from '@/lib/supabase/server'
import { scheduleDocumentOutboxWake } from '@/lib/outbox/wake'

export const reprocessScopes = ['extract', 'ocr', 'relationships', 'search_index', 'full'] as const
export type ReprocessScope = typeof reprocessScopes[number]

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function isReprocessScope(scope: unknown): scope is ReprocessScope {
  return typeof scope === 'string' && (reprocessScopes as readonly string[]).includes(scope)
}

export function isReprocessIdempotencyKey(value: unknown): value is string {
  return typeof value === 'string' && uuidPattern.test(value)
}

export async function reprocessDocument(
  documentId: string,
  scope: ReprocessScope,
  idempotencyKey: string,
) {
  if (!uuidPattern.test(documentId) || !isReprocessScope(scope) || !isReprocessIdempotencyKey(idempotencyKey)) {
    return { error: 'Choose one supported reprocessing scope.' }
  }
  if (scope !== 'search_index') {
    return { error: 'Only Search index reprocessing is available. Other scopes are unavailable until their dedicated workers are deployed.' }
  }

  const supabase = await createClient()
  const { data: contexts, error: contextError } = await supabase.rpc('get_my_organisation_context')
  const context = contexts?.find((candidate) => candidate.state === 'active')
  if (contextError || !context) return { error: 'Your active organisation could not be verified.' }

  const { data, error } = await supabase.rpc('request_document_reprocess', {
    p_document_id: documentId,
    p_scope: scope,
    p_idempotency: idempotencyKey,
    p_capability_version: context.capability_version,
  })
  const result = data?.[0]
  if (error || !result) return { error: 'Could not queue search-index reprocessing. Please try again.' }
  if (result.code === 'queued' || result.code === 'already_requested') {
    // This is only a best-effort latency hint. The durable outbox and its
    // scheduled dispatcher remain authoritative if Trigger is unavailable.
    scheduleDocumentOutboxWake()
    return { success: true, status: result.code === 'queued' ? 'queued' : 'already_queued' }
  }
  if (result.code === 'not_available') return { error: 'This document version is no longer available for reprocessing.' }
  if (result.code === 'not_allowed' || result.code === 'capability_version_mismatch') return { error: 'You no longer have permission to reprocess this document.' }
  if (result.code === 'idempotency_conflict') return { error: 'This request key was already used for a different reprocessing request.' }
  if (result.code === 'scope_unavailable') return { error: 'This reprocessing scope is unavailable until its dedicated worker is deployed.' }
  return { error: 'Search-index reprocessing could not be queued.' }
}
