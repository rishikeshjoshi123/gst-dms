import { z } from 'zod'

export const legalDeadlineTypeSchema = z.enum([
  'reply_due', 'appeal_due', 'payment_or_predeposit_due',
  'compliance_due', 'stay_application_due', 'other_legal',
])
export type LegalDeadlineType = z.infer<typeof legalDeadlineTypeSchema>

const dateOnlySchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine((value) => {
  const [year, month, day] = value.split('-').map(Number)
  const parsed = new Date(Date.UTC(year, month - 1, day))
  return parsed.getUTCFullYear() === year && parsed.getUTCMonth() === month - 1 && parsed.getUTCDate() === day
}, 'Enter a real calendar date.')

const concise = (max: number) => z.string().trim().min(2).max(max).refine((value) => !/[\u0000-\u001f\u007f]/.test(value))
const commandBase = z.object({
  matterId: z.string().uuid(),
  title: concise(160),
  obligation: concise(1000),
  legalType: legalDeadlineTypeSchema,
  dueDate: dateOnlySchema,
  manualBasis: concise(500),
  idempotencyKey: z.string().uuid(),
})

export const createManualDeadlineSchema = commandBase
export const amendManualDeadlineSchema = commandBase.extend({
  deadlineId: z.string().uuid(), expectedRevision: z.number().int().positive(), reason: concise(500),
})
export const deadlineOutcomeSchema = z.object({
  matterId: z.string().uuid(), deadlineId: z.string().uuid(), expectedRevision: z.number().int().positive(),
  outcome: z.enum(['satisfied', 'cancelled']), reason: z.string().trim().max(500), idempotencyKey: z.string().uuid(),
}).superRefine((value, context) => {
  if (value.outcome === 'cancelled' && value.reason.length < 2) context.addIssue({ code: 'custom', path: ['reason'], message: 'A cancellation reason is required.' })
  if (value.reason && (value.reason.length < 2 || /[\u0000-\u001f\u007f]/.test(value.reason))) context.addIssue({ code: 'custom', path: ['reason'], message: 'Enter a valid reason.' })
})

export type DeadlineHistoryItem = {
  kind: 'created' | 'amended' | 'satisfied' | 'cancelled'
  revision: number
  at: string
  actor_label: string
  title?: string
  obligation?: string
  legal_type?: LegalDeadlineType
  due_date?: string
  manual_basis?: string
  reason?: string | null
}
export type ManualDeadlineItem = {
  id: string
  title: string
  obligation: string
  legal_type: LegalDeadlineType
  due_date: string
  manual_basis: string
  origin: 'manual'
  verification_state: 'verified'
  lifecycle: 'open' | 'satisfied' | 'cancelled'
  temporal: 'upcoming' | 'due_soon' | 'due_today' | 'missed'
  revision: number
  created_at: string
  updated_at: string
  history: DeadlineHistoryItem[]
}
export type ManualDeadlineAgenda = {
  items: ManualDeadlineItem[]
  timezone: string
  asOfDate: string
  canMutate: boolean
}

const historySchema = z.object({
  kind: z.enum(['created', 'amended', 'satisfied', 'cancelled']), revision: z.number().int().positive(), at: z.string(), actor_label: z.string().min(1),
  title: z.string().optional(), obligation: z.string().optional(), legal_type: legalDeadlineTypeSchema.optional(), due_date: dateOnlySchema.optional(), manual_basis: z.string().optional(), reason: z.string().nullable().optional(),
})
const itemSchema = z.object({
  id: z.string().uuid(), title: z.string(), obligation: z.string(), legal_type: legalDeadlineTypeSchema, due_date: dateOnlySchema, manual_basis: z.string().min(2),
  origin: z.literal('manual'), verification_state: z.literal('verified'), lifecycle: z.enum(['open', 'satisfied', 'cancelled']),
  temporal: z.enum(['upcoming', 'due_soon', 'due_today', 'missed']), revision: z.number().int().positive(), created_at: z.string(), updated_at: z.string(), history: z.array(historySchema),
})
export const agendaRowSchema = z.object({ items: z.array(itemSchema), timezone: z.string().min(1), as_of_date: dateOnlySchema, can_mutate: z.boolean() })

export const DEADLINE_TYPE_LABELS: Record<LegalDeadlineType, string> = {
  reply_due: 'Reply due', appeal_due: 'Appeal due', payment_or_predeposit_due: 'Payment or pre-deposit due',
  compliance_due: 'Compliance due', stay_application_due: 'Stay application due', other_legal: 'Other legal deadline',
}
export const TEMPORAL_LABELS: Record<ManualDeadlineItem['temporal'], string> = {
  upcoming: 'Upcoming', due_soon: 'Due soon', due_today: 'Due today', missed: 'Missed',
}

export function deadlineCommandMessage(code: string) {
  return ({
    ok: 'Saved.', invalid_request: 'Check every field and enter a valid date.', not_allowed: 'This deadline cannot be changed.',
    stale_revision: 'The deadline changed. Review the latest version and try again.',
    idempotency_conflict: 'This submission key was already used for a different deadline change.',
  } as Record<string, string>)[code] ?? 'The change could not be confirmed. Try again.'
}
