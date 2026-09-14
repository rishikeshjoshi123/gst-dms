'use server'

import { refresh, revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { amendManualDeadlineSchema, createManualDeadlineSchema, deadlineCommandMessage, deadlineOutcomeSchema } from '@/lib/deadlines/manual'

type Result = { code: string; message: string; revision?: number; replayed?: boolean }
function result(code: string, revision?: number, replayed?: boolean): Result { return { code, message: deadlineCommandMessage(code), revision, replayed } }

async function invoke(name: 'create_manual_legal_deadline' | 'amend_manual_legal_deadline' | 'record_manual_legal_deadline_outcome', args: Record<string, unknown>, matterId: string) {
  const client = await createClient()
  const { data: auth, error: authError } = await client.auth.getUser()
  if (authError || !auth.user) return result('not_allowed')
  const { data, error } = await client.rpc(name, args as never)
  const row = (data as Array<{ code: string; revision: number; replayed: boolean }> | null)?.[0]
  const output = result(error ? 'unknown' : row?.code ?? 'unknown', row?.revision, row?.replayed)
  if (output.code === 'ok') { revalidatePath(`/matters/${matterId}`); refresh() }
  return output
}

export async function createManualLegalDeadline(input: unknown) {
  const parsed = createManualDeadlineSchema.safeParse(input)
  if (!parsed.success) return result('invalid_request')
  const v = parsed.data
  return invoke('create_manual_legal_deadline', { p_matter_id:v.matterId,p_title:v.title,p_obligation:v.obligation,p_legal_type:v.legalType,p_due_date:v.dueDate,p_manual_basis:v.manualBasis,p_idempotency_key:v.idempotencyKey }, v.matterId)
}
export async function amendManualLegalDeadline(input: unknown) {
  const parsed = amendManualDeadlineSchema.safeParse(input)
  if (!parsed.success) return result('invalid_request')
  const v = parsed.data
  return invoke('amend_manual_legal_deadline', { p_deadline_id:v.deadlineId,p_expected_revision:v.expectedRevision,p_title:v.title,p_obligation:v.obligation,p_legal_type:v.legalType,p_due_date:v.dueDate,p_manual_basis:v.manualBasis,p_reason:v.reason,p_idempotency_key:v.idempotencyKey }, v.matterId)
}
export async function recordManualLegalDeadlineOutcome(input: unknown) {
  const parsed = deadlineOutcomeSchema.safeParse(input)
  if (!parsed.success) return result('invalid_request')
  const v = parsed.data
  return invoke('record_manual_legal_deadline_outcome', { p_deadline_id:v.deadlineId,p_expected_revision:v.expectedRevision,p_outcome:v.outcome,p_reason:v.reason,p_idempotency_key:v.idempotencyKey }, v.matterId)
}
