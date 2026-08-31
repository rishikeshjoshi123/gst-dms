'use server'

import { revalidatePath } from 'next/cache'

import { getCurrentOrgId } from '@/lib/actions/org'
import { createClient } from '@/lib/supabase/server'

export type UpdateTrashRetentionResult = {
  error?: string
  retentionDays?: 30 | 60 | 90
  policyVersion?: number
  updatedAt?: string
  success?: true
}

function isRetentionDays(value: number): value is 30 | 60 | 90 {
  return value === 30 || value === 60 || value === 90
}

export async function updateTrashRetentionPolicy(
  retentionDays: number,
  expectedPolicyVersion: number,
): Promise<UpdateTrashRetentionResult> {
  if (!isRetentionDays(retentionDays) || !Number.isInteger(expectedPolicyVersion) || expectedPolicyVersion < 1) {
    return { error: 'Choose a valid retention period and try again.' }
  }

  const supabase = await createClient()
  const [{ data: authData }, orgId] = await Promise.all([
    supabase.auth.getUser(),
    getCurrentOrgId(),
  ])
  if (!authData.user) return { error: 'Sign in again to change this setting.' }
  if (!orgId) return { error: 'No active organisation is available.' }

  const { data, error } = await supabase.rpc('update_organisation_trash_retention_policy', {
    p_org_id: orgId,
    p_trash_retention_days: retentionDays,
    p_expected_policy_version: expectedPolicyVersion,
  })
  const result = data?.[0]
  if (error || !result) return { error: 'Trash retention could not be updated. Try again.' }

  const currentDays = Number(result.trash_retention_days)
  const currentVersion = Number(result.policy_version)
  const current = isRetentionDays(currentDays) && Number.isInteger(currentVersion)
    ? { retentionDays: currentDays, policyVersion: currentVersion, updatedAt: result.updated_at ?? undefined }
    : {}

  if (result.code === 'updated') {
    revalidatePath('/settings')
    revalidatePath('/dashboard')
    return { success: true, ...current }
  }
  if (result.code === 'conflict') {
    return { error: 'This policy changed in another session. The latest value is shown; review it before saving again.', ...current }
  }
  if (result.code === 'not_allowed') return { error: 'Only an Owner or Admin can change Trash retention.' }
  return { error: 'Trash retention could not be updated. Refresh and try again.', ...current }
}
