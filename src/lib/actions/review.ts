'use server'
import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { reviewResolution, reviewDetail, type ReviewResolution } from '@/lib/review/model'

export async function resolveExtractionConflict(input: ReviewResolution) {
  const request = reviewResolution.safeParse(input)
  if (!request.success) return { code: 'invalid_request', message: 'Choose an outcome and enter a reason of up to 500 characters.', item: null }
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('resolve_extraction_conflict', {
    p_review_item_id: request.data.itemId, p_expected_revision: request.data.revision, p_action: request.data.action,
    p_candidate_id: request.data.candidateId, p_reason: request.data.reason, p_idempotency_key: request.data.idempotencyKey,
  })
  if (error || !data?.[0]) return { code: 'failed', message: 'The decision could not be recorded. Retry this confirmation.', item: null }
  const result = data[0]
  const item = result.current_item ? reviewDetail.parse(result.current_item) : null
  revalidatePath('/review')
  revalidatePath('/dashboard')
  if (item) { revalidatePath(`/documents/${item.document_id}`); revalidatePath('/matters', 'layout') }
  const messages: Record<string, string> = {
    ok: request.data.action === 'select_candidate' ? 'Decision recorded. Review closed.' : 'Clarification requested. This item still needs review.',
    stale: 'This item changed. The current state is shown; review it before deciding.',
    forbidden: 'Your current access does not allow Review decisions.', unavailable: 'This item is no longer available.',
    idempotency_conflict: 'This confirmation was already used for a different decision. Review the current item.',
    invalid_candidate: 'This candidate cannot resolve the conflict. Review the available outcomes.',
    invalid_request: 'Choose an outcome and enter a reason of up to 500 characters.',
  }
  return { code: result.code, message: messages[result.code] ?? 'The decision was not completed.', item }
}
