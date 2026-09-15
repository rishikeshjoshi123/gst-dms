'use server'
import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { ambiguousPlacementResolution, deadlineReviewResolution, extractionReviewResolution, processingRecoveryResolution, reviewDetail, type AmbiguousPlacementResolution, type DeadlineReviewResolution, type ExtractionReviewResolution, type ProcessingRecoveryResolution } from '@/lib/review/model'

export async function resolveExplicitDueDate(input: DeadlineReviewResolution) {
  const request=deadlineReviewResolution.safeParse(input)
  if(!request.success) return {code:'invalid_request',message:'Choose an outcome, valid date when correcting, and a reason.',item:null}
  const supabase=await createClient()
  const {data,error}=await supabase.rpc('resolve_explicit_due_date_review',{
    p_review_item_id:request.data.itemId,p_expected_revision:request.data.revision,
    p_action:request.data.action,p_corrected_due_date:request.data.correctedDueDate,
    p_reason:request.data.reason,p_idempotency_key:request.data.idempotencyKey,
  } as never)
  if(error || !data?.[0]) return {code:'failed',message:'The date decision could not be confirmed. Retry.',item:null}
  const row=data[0],item=row.current_item?reviewDetail.parse(row.current_item):null
  if(row.code==='ok'){
    revalidatePath('/review')
    revalidatePath('/dashboard')
    if(item?.document_id){revalidatePath('/matters','layout');revalidatePath(`/documents/${item.document_id}`)}
  }
  const messages:Record<string,string>={
    ok:'Date decision recorded with its cited source and reason.',
    stale:'The source or decision changed. Inspect the latest state.',
    forbidden:'You cannot decide legal dates with your current access.',
    unavailable:'The exact source is no longer available.',
    idempotency_conflict:'This submission key was used for another decision.',
    invalid_request:'Choose an outcome, valid date when correcting, and a reason.',
  }
  return {code:row.code,message:messages[row.code]??'The decision was not completed.',item}
}

export async function resolveExtractionConflict(input: ExtractionReviewResolution) {
  const request = extractionReviewResolution.safeParse(input)
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
  if (item?.document_id) { revalidatePath(`/documents/${item.document_id}`); revalidatePath('/matters', 'layout') }
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

export async function continueProcessingManually(input: ProcessingRecoveryResolution) {
  const request = processingRecoveryResolution.safeParse(input)
  if (!request.success) return { code: 'invalid_request', message: 'Enter the required document details and a reason of up to 500 characters.', item: null }
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('resolve_processing_recovery', {
    p_review_item_id: request.data.itemId, p_expected_revision: request.data.revision,
    p_action: request.data.action, p_metadata: request.data.metadata,
    p_reason: request.data.reason, p_idempotency_key: request.data.idempotencyKey,
  })
  if (error || !data?.[0]) return { code: 'failed', message: 'Manual continuation could not be recorded. Retry this confirmation.', item: null }
  const result = data[0]
  const item = result.current_item ? reviewDetail.parse(result.current_item) : null
  revalidatePath('/review')
  revalidatePath('/dashboard')
  if (item?.document_id) { revalidatePath(`/documents/${item.document_id}`); revalidatePath('/matters', 'layout') }
  const messages: Record<string, string> = {
    ok: 'Manual metadata recorded. Review closed; continue in the document Workbench.',
    stale: 'This item or source changed. The current state is shown; review it before continuing.',
    forbidden: 'Your current access does not allow Review decisions.', unavailable: 'This item is no longer available.',
    idempotency_conflict: 'This confirmation was already used for different manual details. Review the current item.',
    invalid_request: 'Enter the required document details and a reason of up to 500 characters.',
  }
  return { code: result.code, message: messages[result.code] ?? 'Manual continuation was not completed.', item }
}

export async function resolveAmbiguousPlacement(input: AmbiguousPlacementResolution) {
  const request = ambiguousPlacementResolution.safeParse(input)
  if (!request.success) return { code: 'invalid_request', message: 'Choose an eligible destination and enter a reason of up to 500 characters.', item: null, matterId: null, documentId: null, documentVersionId: null, lifecycleRevision: null }
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('resolve_ambiguous_intake_placement', {
    p_review_item_id: request.data.itemId, p_expected_revision: request.data.revision,
    p_placement_candidate_id: request.data.placementCandidateId, p_reason: request.data.reason,
    p_idempotency_key: request.data.idempotencyKey,
  })
  if (error || !data?.[0]) return { code: 'failed', message: 'The placement could not be recorded. Retry this confirmation.', item: null, matterId: null, documentId: null, documentVersionId: null, lifecycleRevision: null }
  const result = data[0]
  const item = result.current_item ? reviewDetail.parse(result.current_item) : null
  revalidatePath('/review')
  revalidatePath('/documents')
  revalidatePath('/matters', 'layout')
  const messages: Record<string, string> = {
    ok: 'Destination recorded. The Intake PDF is now available in its exact document Workbench.',
    stale: 'This Intake, evidence, or destination changed. Review the current state before deciding.',
    forbidden: 'Your current access does not allow Review decisions.', unavailable: 'This item is no longer available.',
    idempotency_conflict: 'This confirmation was already used for a different placement. Review the current item.',
    invalid_request: 'Choose an eligible destination and enter a reason of up to 500 characters.',
  }
  return { code: result.code, message: messages[result.code] ?? 'The placement was not completed.', item,
    matterId: result.matter_id, documentId: result.document_id, documentVersionId: result.document_version_id,
    lifecycleRevision: result.lifecycle_revision }
}
