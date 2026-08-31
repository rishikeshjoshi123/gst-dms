'use server'

import { revalidatePath } from 'next/cache'

import { createClient } from '@/lib/supabase/server'
import { scheduleTrashPurgeWake } from '@/lib/trash/purge-wake'

export type TrashPurgeActionResult = { success: boolean; code: string; error?: string }

export async function reauthenticateTrashPurgeAction(password: string): Promise<TrashPurgeActionResult> {
  if (typeof password !== 'string' || password.length < 1 || password.length > 1024) {
    return { success: false, code: 'invalid_password', error: 'Enter your current password.' }
  }
  const supabase = await createClient()
  const { data: authData } = await supabase.auth.getUser()
  if (!authData.user?.email) return { success: false, code: 'not_authenticated', error: 'Sign in again to continue.' }
  const { error } = await supabase.auth.signInWithPassword({ email: authData.user.email, password })
  if (error) return { success: false, code: 'invalid_password', error: 'Your password was not accepted.' }
  return { success: true, code: 'reauthenticated' }
}

export async function confirmTrashPurgeAction(input: {
  operationId: string
  impactFingerprint: string
  confirmationText: string
  idempotencyKey: string
}): Promise<TrashPurgeActionResult> {
  const supabase = await createClient()
  const { data: authData } = await supabase.auth.getUser()
  if (!authData.user) return { success: false, code: 'not_authenticated', error: 'Sign in again to continue.' }
  const { data, error } = await supabase.rpc('confirm_trash_purge', {
    p_operation_id: input.operationId,
    p_impact_fingerprint: input.impactFingerprint,
    p_confirmation_text: input.confirmationText,
    p_idempotency_key: input.idempotencyKey,
  })
  const result = data?.[0]
  if (error || !result) return { success: false, code: 'failed', error: 'Permanent deletion could not be queued. Try again.' }
  if (result.code === 'queued' || result.code === 'already_queued') {
    revalidatePath('/trash')
    revalidatePath(`/trash/${input.operationId}/permanent-delete`)
    scheduleTrashPurgeWake()
    return { success: true, code: result.code }
  }
  const message: Record<string, string> = {
    not_allowed: 'Only an Owner or Admin can permanently delete this Trash group.',
    recent_auth_required: 'Verify your identity again before confirming permanent deletion.',
    confirmation_mismatch: 'The confirmation text does not match exactly.',
    stale_impact: 'The impact changed. Reload and review the current impact before confirming.',
    blocked: 'A legal hold, export, backup, or platform dependency blocks this whole Trash group.',
    not_available: 'This Trash group is no longer available for permanent deletion.',
  }
  return { success: false, code: result.code, error: message[result.code] ?? 'Permanent deletion could not be queued.' }
}

export async function retryTrashPurgeAction(input: {
  operationId: string
  impactFingerprint: string
  idempotencyKey: string
}): Promise<TrashPurgeActionResult> {
  const supabase = await createClient()
  const { data: authData } = await supabase.auth.getUser()
  if (!authData.user) return { success: false, code: 'not_authenticated', error: 'Sign in again to continue.' }
  const { data, error } = await supabase.rpc('retry_trash_purge', {
    p_operation_id: input.operationId,
    p_impact_fingerprint: input.impactFingerprint,
    p_idempotency_key: input.idempotencyKey,
  })
  const result = data?.[0]
  if (error || !result) return { success: false, code: 'failed', error: 'Permanent deletion could not be retried. Try again.' }
  if (result.code === 'retried') {
    revalidatePath('/trash')
    revalidatePath(`/trash/${input.operationId}/permanent-delete`)
    scheduleTrashPurgeWake()
    return { success: true, code: result.code }
  }
  const message: Record<string, string> = {
    not_allowed: 'Only an Owner or Admin can retry permanent deletion.',
    recent_auth_required: 'Verify your identity again before retrying permanent deletion.',
    stale_impact: 'The operational impact changed. Reload before retrying.',
    blocked: 'A legal hold, export, backup, or platform dependency blocks this whole Trash group.',
    not_available: 'This permanent deletion cannot be retried from its current state.',
  }
  return { success: false, code: result.code, error: message[result.code] ?? 'Permanent deletion could not be retried.' }
}
