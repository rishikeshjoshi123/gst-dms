import { z } from 'zod'

export const reviewAction = z.enum(['select_candidate', 'request_clarification'])
export const reviewQueueItem = z.object({
  id: z.string().uuid(), type: z.literal('extraction_conflict'), field_path: z.string(),
  priority: z.enum(['normal', 'high', 'urgent']), priority_reason: z.string(),
  status: z.enum(['needs_review', 'closed']), closure_reason: z.enum(['decision_recorded', 'source_replaced']).nullable(),
  revision: z.number().int().positive(), created_at: z.string(),
  document_id: z.string().uuid(), document_version_id: z.string().uuid(),
  document_title: z.string().nullable(), matter_title: z.string(), client_name: z.string(),
})
export const reviewDetail = reviewQueueItem.extend({
  impact: z.string(), version_number: z.number().int(), is_current: z.boolean(),
  allowed_actions: z.array(reviewAction),
  evidence: z.array(z.object({
    candidate_id: z.string().uuid(), ordinal: z.number().int(), selectable: z.boolean(),
    page_number: z.number().int().positive(), quotation: z.string(), value: z.unknown(),
    validation_state: z.enum(['eligible', 'provisional', 'conflicting', 'invalid']),
  })),
  last_decision: z.object({ action: reviewAction, selected_candidate_id: z.string().uuid().nullable(), reason: z.string(), created_at: z.string() }).nullable(),
})
export type ReviewQueueItem = z.infer<typeof reviewQueueItem>
export type ReviewDetail = z.infer<typeof reviewDetail>
export type ReviewFilters = { status: 'needs_review' | 'closed' | 'all'; type: 'extraction_conflict' | 'all'; priority: 'normal' | 'high' | 'urgent' | 'all'; search: string; page: number; item?: string; tab: 'evidence' | 'decision' }
export const reviewResolution = z.object({
  itemId: z.string().uuid(), revision: z.number().int().positive(), action: reviewAction,
  candidateId: z.string().uuid().nullable(), reason: z.string().trim().min(1).max(500).refine(value => !/[\u0000-\u001f\u007f]/.test(value)),
  idempotencyKey: z.string().uuid(),
}).strict().refine(value => (value.action === 'select_candidate') === (value.candidateId !== null))
export type ReviewResolution = z.infer<typeof reviewResolution>

export function parseReviewFilters(params: Record<string, string | string[] | undefined>): ReviewFilters {
  const page = typeof params.page === 'string' && /^[1-9]\d{0,5}$/.test(params.page) ? Number(params.page) : 1
  return {
    status: params.status === 'closed' || params.status === 'all' ? params.status : 'needs_review',
    type: params.type === 'extraction_conflict' ? params.type : 'all',
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
