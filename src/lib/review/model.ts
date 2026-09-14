import { z } from 'zod'

export const reviewAction = z.enum(['select_candidate', 'request_clarification', 'continue_manual'])
const reviewQueueBase = z.object({
  id: z.string().uuid(),
  priority: z.enum(['normal', 'high', 'urgent']), priority_reason: z.string(),
  status: z.enum(['needs_review', 'closed']), closure_reason: z.enum(['decision_recorded', 'source_replaced']).nullable(),
  revision: z.number().int().positive(), created_at: z.string(),
  document_id: z.string().uuid(), document_version_id: z.string().uuid(),
  document_title: z.string().nullable(), matter_title: z.string(), client_name: z.string(),
})
export const reviewQueueItem = z.discriminatedUnion('type', [
  reviewQueueBase.extend({ type: z.literal('extraction_conflict'), field_path: z.string(), reason_code: z.literal('material_candidate_conflict'), impact: z.string() }),
  reviewQueueBase.extend({ type: z.literal('processing_recovery'), field_path: z.null(), reason_code: z.enum(['invalid_model_output', 'provider_failed', 'domain_invalid']), impact: z.string(), source_page_number: z.literal(1) }),
])
const reviewDetailBase = z.object({
  impact: z.string(), version_number: z.number().int(), is_current: z.boolean(),
  source_identity: z.string(), allowed_actions: z.array(reviewAction),
  record_baseline: z.object({ value: z.string(), origin_kind: z.string(), captured_at: z.string() }).nullable().optional(),
  evidence: z.array(z.object({
    candidate_id: z.string().uuid(), ordinal: z.number().int(), selectable: z.boolean(),
    page_number: z.number().int().positive(), quotation: z.string(), value: z.unknown(),
    validation_state: z.enum(['eligible', 'provisional', 'conflicting', 'invalid']),
  })),
  last_decision: z.object({ action: reviewAction, selected_candidate_id: z.string().uuid().nullable(), manual_metadata: z.unknown().nullable().optional(), reason: z.string(), created_at: z.string() }).nullable(),
})
export const reviewDetail = z.intersection(reviewQueueItem, reviewDetailBase)
export type ReviewQueueItem = z.infer<typeof reviewQueueItem>
export type ReviewDetail = z.infer<typeof reviewDetail>
export type ReviewFilters = { status: 'needs_review' | 'closed' | 'all'; type: 'extraction_conflict' | 'processing_recovery' | 'all'; priority: 'normal' | 'high' | 'urgent' | 'all'; search: string; page: number; item?: string; tab: 'evidence' | 'decision' }
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

export function parseReviewFilters(params: Record<string, string | string[] | undefined>): ReviewFilters {
  const page = typeof params.page === 'string' && /^[1-9]\d{0,5}$/.test(params.page) ? Number(params.page) : 1
  return {
    status: params.status === 'closed' || params.status === 'all' ? params.status : 'needs_review',
    type: params.type === 'extraction_conflict' || params.type === 'processing_recovery' ? params.type : 'all',
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
