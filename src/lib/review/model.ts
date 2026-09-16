import { z } from 'zod'

export const reviewAction = z.enum(['select_candidate', 'request_clarification', 'continue_manual', 'select_destination',
  'verify_deadline','correct_deadline','reject_deadline','clear_deadline','verify','correct','reject','clear',
  'keep_placement','move_placement','keep','move','distinct_documents','possible_same_document'])
const reviewQueueBase = z.object({
  id: z.string().uuid(),
  priority: z.enum(['normal', 'high', 'urgent']), priority_reason: z.string(),
  status: z.enum(['needs_review', 'closed']), closure_reason: z.enum(['decision_recorded', 'source_replaced', 'source_unavailable']).nullable(),
  revision: z.number().int().positive(), created_at: z.string(),
  document_title: z.string().nullable(), matter_title: z.string(), client_name: z.string(),
  source_count:z.number().int().min(2).max(8).nullable().optional(),
})
const documentReviewQueueBase = reviewQueueBase.extend({ document_id: z.string().uuid(), document_version_id: z.string().uuid(), intake_id: z.null().optional() })
export const reviewQueueItem = z.discriminatedUnion('type', [
  documentReviewQueueBase.extend({ type: z.literal('extraction_conflict'), field_path: z.string(), reason_code: z.literal('material_candidate_conflict'), impact: z.string() }),
  documentReviewQueueBase.extend({ type: z.literal('processing_recovery'), field_path: z.null(), reason_code: z.enum(['invalid_model_output', 'provider_failed', 'domain_invalid']), impact: z.string(), source_page_number: z.literal(1) }),
  documentReviewQueueBase.extend({ type: z.literal('deadline_verification'), field_path: z.literal('document.legal_date.due'), reason_code: z.literal('source_stated_due_date'), impact: z.string() }),
  documentReviewQueueBase.extend({ type: z.literal('placement_conflict'), field_path: z.literal('document.official_reference.self_identifier'), reason_code: z.literal('verified_matter_identity_mismatch'), impact: z.string(), source_page_number: z.number().int().positive() }),
  documentReviewQueueBase.extend({ type: z.literal('multi_placement_conflict'), field_path: z.literal('document.official_reference.self_identifier'), reason_code: z.literal('multiple_verified_matter_identity_mismatches'), impact: z.string(), source_page_number: z.number().int().positive() }),
  documentReviewQueueBase.extend({ type: z.literal('possible_duplicate'), field_path: z.literal('document.official_reference.self_identifier'), reason_code: z.literal('shared_verified_document_identifier'), impact: z.string(), source_page_number: z.number().int().positive() }),
  reviewQueueBase.extend({ type: z.literal('ambiguous_placement'), field_path: z.null(), reason_code: z.literal('multiple_eligible_matters'), impact: z.string(), source_page_number: z.literal(1), intake_id: z.string().uuid(), document_id: z.null(), document_version_id: z.null() }),
])
const reviewDetailBase = z.object({
  impact: z.string(), version_number: z.number().int().nullable(), is_current: z.boolean(),
  source_identity: z.string(), allowed_actions: z.array(reviewAction),
  record_baseline: z.object({ value: z.string(), origin_kind: z.string(), captured_at: z.string() }).nullable().optional(),
  evidence: z.array(z.object({
    candidate_id: z.string().uuid(), ordinal: z.number().int(), selectable: z.boolean(),
    page_number: z.number().int().positive(), quotation: z.string(), value: z.unknown(),
    validation_state: z.enum(['eligible', 'provisional', 'conflicting', 'invalid']),
  })),
  last_decision: z.object({ action: reviewAction, selected_candidate_id: z.string().uuid().nullable(), selected_document_ids:z.array(z.string().uuid()).optional(), placement_candidate_id: z.string().uuid().nullable().optional(), result_matter_id: z.string().uuid().nullable().optional(), result_document_id: z.string().uuid().nullable().optional(), result_document_version_id: z.string().uuid().nullable().optional(), result_lifecycle_revision: z.number().int().positive().nullable().optional(), manual_metadata: z.unknown().nullable().optional(), reason: z.string(), created_at: z.string() }).nullable(),
  deadline_id:z.string().uuid().optional(), deadline_revision:z.number().int().positive().optional(),
  candidate_due_date:z.string().optional(), decision_history:z.array(z.object({
    action:z.enum(['verify','correct','reject','clear']),due_date:z.string().nullable(),
    reason:z.string(),decided_at:z.string(),
  })).optional(),
  old_matter_id:z.string().uuid().optional(),old_matter_code:z.string().optional(),
  current_matter_id:z.string().uuid().nullable().optional(),current_matter_title:z.string().nullable().optional(),
  current_matter_code:z.string().nullable().optional(),
  target_matter_id:z.string().uuid().optional(),target_matter_code:z.string().optional(),
  target_matter_title:z.string().optional(),target_client_name:z.string().optional(),
  target_identifier_id:z.string().uuid().optional(),target_identifier_revision:z.number().int().positive().optional(),
  identifier_kind:z.string().optional(),issuer_namespace_normalized:z.string().optional(),
  normalized_value:z.string().optional(),display_value:z.string().optional(),target_verified_at:z.string().optional(),
  source_analysis_run_id:z.string().uuid().optional(),source_candidate_id:z.string().uuid().optional(),
  source_quote:z.string().optional(),
  conflict_current:z.boolean().optional(),
})
export const reviewDetail = z.intersection(reviewQueueItem, reviewDetailBase)
export type ReviewQueueItem = z.infer<typeof reviewQueueItem>
export type ReviewDetail = z.infer<typeof reviewDetail>
export type ReviewFilters = { status: 'needs_review' | 'closed' | 'all'; type: 'extraction_conflict' | 'processing_recovery' | 'ambiguous_placement' | 'deadline_verification' | 'placement_conflict' | 'multi_placement_conflict' | 'possible_duplicate' | 'all'; priority: 'normal' | 'high' | 'urgent' | 'all'; search: string; page: number; item?: string; tab: 'evidence' | 'decision' }
export const possibleDuplicateResolution=z.object({
  itemId:z.string().uuid(),revision:z.number().int().positive(),action:z.enum(['distinct_documents','possible_same_document']),
  selectedDocumentIds:z.array(z.string().uuid()).max(8),
  reason:z.string().trim().min(2).max(500).refine(value=>!/[\u0000-\u001f\u007f]/.test(value)),
  idempotencyKey:z.string().uuid(),
}).strict().superRefine((value,context)=>{
  const count=value.selectedDocumentIds.length
  if(new Set(value.selectedDocumentIds).size!==count || (value.action==='distinct_documents'&&count!==0) || (value.action==='possible_same_document'&&count<2))
    context.addIssue({code:'custom',path:['selectedDocumentIds'],message:'Name at least two distinct current documents only for a possible-same finding.'})
})
export type PossibleDuplicateResolution=z.infer<typeof possibleDuplicateResolution>
export const placementConflictResolution=z.object({
  itemId:z.string().uuid(),revision:z.number().int().positive(),action:z.enum(['keep','move']),
  impactFingerprint:z.string().regex(/^[0-9a-f]{64}$/).nullable(),
  reason:z.string().trim().min(2).max(500).refine(value=>!/[\u0000-\u001f\u007f]/.test(value)),
  idempotencyKey:z.string().uuid(),
}).strict().refine(value=>(value.action==='move')===(value.impactFingerprint!==null))
export type PlacementConflictResolution=z.infer<typeof placementConflictResolution>
export const multiPlacementConflictResolution=z.object({
  itemId:z.string().uuid(),revision:z.number().int().positive(),action:z.enum(['keep','move']),
  targetMatterId:z.string().uuid().nullable(),impactFingerprint:z.string().regex(/^[0-9a-f]{64}$/).nullable(),
  reason:z.string().trim().min(2).max(500).refine(value=>!/[\u0000-\u001f\u007f]/.test(value)),
  idempotencyKey:z.string().uuid(),
}).strict().refine(value=>value.action==='move' ? value.targetMatterId!==null&&value.impactFingerprint!==null : value.targetMatterId===null&&value.impactFingerprint===null)
export type MultiPlacementConflictResolution=z.infer<typeof multiPlacementConflictResolution>
export const deadlineReviewResolution = z.object({
  itemId:z.string().uuid(),revision:z.number().int().positive(),
  action:z.enum(['verify','correct','reject','clear']),correctedDueDate:z.string().nullable(),
  reason:z.string().trim().min(2).max(500).refine(value=>!/[\u0000-\u001f\u007f]/.test(value)),
  idempotencyKey:z.string().uuid(),
}).strict().superRefine((value,context)=>{
  const validDate=z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(date=>{
    const parsed=new Date(`${date}T00:00:00Z`)
    return !Number.isNaN(parsed.valueOf())&&parsed.toISOString().slice(0,10)===date
  }).safeParse(value.correctedDueDate).success
  if((value.action==='correct')!==validDate || (value.action!=='correct'&&value.correctedDueDate!==null))
    context.addIssue({code:'custom',path:['correctedDueDate'],message:'Correction requires one real explicit calendar date.'})
})
export type DeadlineReviewResolution=z.infer<typeof deadlineReviewResolution>
export const extractionReviewResolution = z.object({
  itemId: z.string().uuid(), revision: z.number().int().positive(), action: z.enum(['select_candidate', 'request_clarification']),
  candidateId: z.string().uuid().nullable(), reason: z.string().trim().min(1).max(500).refine(value => !/[\u0000-\u001f\u007f]/.test(value)),
  idempotencyKey: z.string().uuid(),
}).strict().refine(value => ['select_candidate', 'request_clarification'].includes(value.action) && (value.action === 'select_candidate') === (value.candidateId !== null))
export type ExtractionReviewResolution = z.infer<typeof extractionReviewResolution>
export const manualRecoveryMetadata = z.object({
  doc_type: z.enum(['DRC-01', 'DRC-01A', 'DRC-01C', 'DRC-03', 'DRC-07', 'SCN', 'OIO', 'OIA', 'APL-01', 'APL-02', 'APL-05', 'STAY', 'REPLY', 'HC_PETITION', 'HC_ORDER', 'SC_PETITION', 'SC_ORDER', 'OTHER']),
  reference_number: z.string().trim().min(1).max(300).refine(value => !/[\u0000-\u001f\u007f]/.test(value)),
  document_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => !Number.isNaN(new Date(`${value}T00:00:00Z`).valueOf()) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value),
  direction: z.enum(['incoming', 'outgoing']),
  issued_by: z.string().trim().min(1).max(300).refine(value => !/[\u0000-\u001f\u007f]/.test(value)),
}).strict()
export const processingRecoveryResolution = z.object({
  itemId: z.string().uuid(), revision: z.number().int().positive(), action: z.literal('continue_manual'),
  metadata: manualRecoveryMetadata,
  reason: z.string().trim().min(1).max(500).refine(value => !/[\u0000-\u001f\u007f]/.test(value)),
  idempotencyKey: z.string().uuid(),
}).strict()
export type ProcessingRecoveryResolution = z.infer<typeof processingRecoveryResolution>
export const ambiguousPlacementResolution = z.object({
  itemId: z.string().uuid(), revision: z.number().int().positive(), action: z.literal('select_destination'),
  placementCandidateId: z.string().uuid(), reason: z.string().trim().min(1).max(500).refine(value => !/[\u0000-\u001f\u007f]/.test(value)),
  idempotencyKey: z.string().uuid(),
}).strict()
export type AmbiguousPlacementResolution = z.infer<typeof ambiguousPlacementResolution>

export function parseReviewFilters(params: Record<string, string | string[] | undefined>): ReviewFilters {
  const page = typeof params.page === 'string' && /^[1-9]\d{0,5}$/.test(params.page) ? Number(params.page) : 1
  return {
    status: params.status === 'closed' || params.status === 'all' ? params.status : 'needs_review',
    type: params.type === 'extraction_conflict' || params.type === 'processing_recovery' || params.type === 'ambiguous_placement' || params.type === 'deadline_verification' || params.type === 'placement_conflict' || params.type === 'multi_placement_conflict' || params.type === 'possible_duplicate' ? params.type : 'all',
    priority: params.priority === 'normal' || params.priority === 'high' || params.priority === 'urgent' ? params.priority : 'all',
    search: typeof params.search === 'string' ? params.search.slice(0, 200) : '', page: Math.min(page, 100000),
    item: typeof params.item === 'string' && z.string().uuid().safeParse(params.item).success ? params.item : undefined,
    tab: params.tab === 'decision' ? 'decision' : 'evidence',
  }
}
export function reviewFieldLabel(path: string) { return path.replace(/^document\./, '').replaceAll('.', ' · ').replaceAll('_', ' ') }
export function reviewValueLabel(value: unknown): string {
  if (typeof value === 'string' || typeof value === 'number') return String(value)
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const fact = value as Record<string, unknown>
    for (const key of ['display', 'normalized_date', 'amount', 'normalized_value', 'raw']) if (typeof fact[key] === 'string') return fact[key]
  }
  return 'Source observation'
}
export function taxPeriodComparison(value: unknown): { printed: string; derived: string } | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const fact = value as Record<string, unknown>
  if (fact.conflict !== true) return null
  const years = (candidate: unknown) => Array.isArray(candidate) && candidate.every(v => typeof v === 'string') ? candidate.join(', ') : 'Unavailable'
  return { printed: years(fact.printed_financial_years), derived: years(fact.derived_financial_years) }
}
