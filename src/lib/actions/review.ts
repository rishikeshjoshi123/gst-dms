'use server'
import { z } from 'zod'
import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { ambiguousPlacementResolution, deadlineReviewResolution, extractionReviewResolution, multiPlacementConflictResolution, placementConflictResolution, possibleDuplicateResolution, processingRecoveryResolution, reviewDetail, type AmbiguousPlacementResolution, type DeadlineReviewResolution, type ExtractionReviewResolution, type MultiPlacementConflictResolution, type PlacementConflictResolution, type PossibleDuplicateResolution, type ProcessingRecoveryResolution } from '@/lib/review/model'

export async function resolvePossibleDuplicate(input:PossibleDuplicateResolution){
  const request=possibleDuplicateResolution.safeParse(input)
  if(!request.success) return {code:'invalid_request',message:'Choose one document interpretation and give a reason.',item:null}
  const supabase=await createClient()
  const {data,error}=await supabase.rpc('resolve_possible_duplicate',{
    p_review_item_id:request.data.itemId,p_expected_revision:request.data.revision,
    p_action:request.data.action,p_reason:request.data.reason,
    p_selected_document_ids:request.data.selectedDocumentIds,p_idempotency_key:request.data.idempotencyKey,
  } as never)
  if(error||!Array.isArray(data)||!data[0]) return {code:'failed',message:'The document comparison decision could not be confirmed.',item:null}
  const row=data[0] as {code:string;current_item:unknown;replayed:boolean}
  const item=row.current_item?reviewDetail.parse(row.current_item):null
  if(row.code==='ok'){revalidatePath('/review');if(item?.document_id)revalidatePath(`/documents/${item.document_id}`)}
  const messages:Record<string,string>={
    ok:request.data.action==='distinct_documents'
      ?'All cited documents recorded as distinct. The unchanged full source set will not raise this Review again.'
      :`Possible-same finding recorded for ${request.data.selectedDocumentIds.length} selected documents only. No PDF or document was changed.`,
    stale:'The sources, official key or Review changed. Compare the current sources before deciding.',
    forbidden:'Your current access cannot resolve this Review.',unavailable:'This Review item is unavailable.',
    idempotency_conflict:'This submission key was already used for another decision.',
    invalid_selection:'Select only current documents in this comparison.',
    busy:'Another source change is in progress. Refresh and retry.',
  }
  return {code:row.code,message:messages[row.code]??'The comparison decision was not completed.',item}
}

export async function previewMultiPlacementConflictMove(itemId:string,targetMatterId:string){
  const item=z.string().uuid().safeParse(itemId),target=z.string().uuid().safeParse(targetMatterId)
  if(!item.success||!target.success) return {code:'invalid_request'}
  const supabase=await createClient()
  const {data,error}=await supabase.rpc('preview_multi_placement_conflict_move',{
    p_review_item_id:item.data,p_target_matter_id:target.data,
  } as never)
  return error||!data||typeof data!=='object' ? {code:'failed'} : data as {code:string;fingerprint?:string;blockers?:string[];categories?:{key:string;label:string;count:number}[];sourceMatterTitle?:string;targetMatterTitle?:string;documentTitle?:string}
}

export async function resolveMultiPlacementConflict(input:MultiPlacementConflictResolution){
  const request=multiPlacementConflictResolution.safeParse(input)
  if(!request.success) return {code:'invalid_request',message:'Choose exactly one eligible Matter for Move, its current impact, and a reason.',item:null}
  const supabase=await createClient()
  const {data,error}=await supabase.rpc('resolve_multi_placement_conflict',{
    p_review_item_id:request.data.itemId,p_expected_revision:request.data.revision,
    p_action:request.data.action,p_target_matter_id:request.data.targetMatterId,
    p_expected_impact_fingerprint:request.data.impactFingerprint,p_reason:request.data.reason,
    p_idempotency_key:request.data.idempotencyKey,
  } as never)
  if(error||!Array.isArray(data)||!data[0]) return {code:'failed',message:'The filed-document decision could not be confirmed.',item:null}
  const row=data[0] as {code:string;current_item:unknown;replayed:boolean}
  const item=row.current_item?reviewDetail.parse(row.current_item):null
  if(row.code==='ok'){
    revalidatePath('/review');revalidatePath('/matters','layout')
    if(item?.document_id) revalidatePath(`/documents/${item.document_id}`)
  }
  const messages:Record<string,string>={
    ok:request.data.action==='move'?'Document moved to the chosen Matter with the exact source retained.':'Current filing kept; unchanged printed and verified evidence will not raise this Review again.',
    stale:'The source, verified candidate set or Review changed. Inspect the current item.',
    stale_preview:'This target’s Move impact changed. Request a new preview.',
    blocked:'This target’s Move is blocked by a current dependency.',
    invalid_target:'This target was not in the eligible candidate set.',
    forbidden:'Your current access cannot resolve this Review.',
    unavailable:'This Review item is unavailable.',
    idempotency_conflict:'This submission key was already used for a different decision.',
    busy:'Another change is in progress. Retry after refreshing.',
  }
  return {code:row.code,message:messages[row.code]??'The filed-document decision was not completed.',item}
}

export async function previewPlacementConflictMove(itemId:string){
  const id=z.string().uuid().safeParse(itemId)
  if(!id.success) return {code:'invalid_request'}
  const supabase=await createClient()
  const {data,error}=await supabase.rpc('preview_placement_conflict_move',{p_review_item_id:id.data})
  return error || !data || typeof data!=='object' ? {code:'failed'} : data as {code:string;fingerprint?:string;blockers?:string[];categories?:{key:string;label:string;count:number}[];sourceMatterTitle?:string;targetMatterTitle?:string;documentTitle?:string}
}

export async function resolvePlacementConflict(input:PlacementConflictResolution){
  const request=placementConflictResolution.safeParse(input)
  if(!request.success) return {code:'invalid_request',message:'Enter a reason and use a current impact preview for Move.',item:null}
  const supabase=await createClient()
  const {data,error}=await supabase.rpc('resolve_placement_conflict',{
    p_review_item_id:request.data.itemId,p_expected_revision:request.data.revision,
    p_action:request.data.action,p_expected_impact_fingerprint:request.data.impactFingerprint,
    p_reason:request.data.reason,p_idempotency_key:request.data.idempotencyKey,
  } as never)
  if(error || !Array.isArray(data) || !data[0]) return {code:'failed',message:'The placement decision could not be confirmed.',item:null}
  const row=data[0] as {code:string;current_item:unknown;replayed:boolean}
  const item=row.current_item?reviewDetail.parse(row.current_item):null
  if(row.code==='ok'){
    revalidatePath('/review');revalidatePath('/matters','layout')
    if(item?.document_id) revalidatePath(`/documents/${item.document_id}`)
  }
  const messages:Record<string,string>={
    ok:request.data.action==='move'?'Document moved with the exact source and Review decision retained.':'Current placement kept; this source evidence will not raise the same conflict again.',
    stale:'The source, verified key or Review decision changed. Inspect the current item.',
    stale_preview:'The impact changed. Request a new Move preview.',blocked:'Move is blocked by a current dependency; keep the filing or resolve it separately.',
    forbidden:'Your current access cannot resolve this Review.',unavailable:'This Review item is unavailable.',
    idempotency_conflict:'This submission key was already used for a different decision.',busy:'Another change is in progress. Retry after refreshing.',
  }
  return {code:row.code,message:messages[row.code]??'The placement decision was not completed.',item}
}

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
