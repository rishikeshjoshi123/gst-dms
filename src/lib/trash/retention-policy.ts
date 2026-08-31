import 'server-only'

import type { Database } from '@/lib/supabase/database.types'
import { createClient } from '@/lib/supabase/server'

type RetentionPolicyRow = Database['public']['Functions']['get_organisation_trash_retention_policy']['Returns'][number]
type TeamAttentionRow = Database['public']['Functions']['get_trash_retention_team_attention']['Returns'][number]

export type TrashRetentionPolicy = {
  retentionDays: 30 | 60 | 90
  policyVersion: number
  updatedAt: string
  canManage: boolean
}

export type TrashRetentionTeamAttentionItem = {
  operationId: string
  resourceType: Database['public']['Enums']['trash_resource_type']
  rootLabel: string
  scheduledPermanentDeletionAt: string
  projectedAt: string
}

function isRetentionDays(value: number): value is 30 | 60 | 90 {
  return value === 30 || value === 60 || value === 90
}

export async function getOrganisationTrashRetentionPolicy(orgId: string) {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_organisation_trash_retention_policy', {
    p_org_id: orgId,
  })
  if (error) return { policy: null, error: true as const }

  const row = data?.[0] as RetentionPolicyRow | undefined
  if (!row || !isRetentionDays(row.trash_retention_days)) {
    return { policy: null, error: true as const }
  }
  return {
    policy: {
      retentionDays: row.trash_retention_days,
      policyVersion: row.policy_version,
      updatedAt: row.updated_at,
      canManage: row.can_manage,
    } satisfies TrashRetentionPolicy,
    error: false as const,
  }
}

export async function getTrashRetentionTeamAttention(orgId: string) {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_trash_retention_team_attention', {
    p_org_id: orgId,
    p_limit: 25,
  })
  if (error) return []
  return ((data ?? []) as TeamAttentionRow[]).map((row) => ({
    operationId: row.operation_id,
    resourceType: row.root_resource_type,
    rootLabel: row.root_label,
    scheduledPermanentDeletionAt: row.scheduled_permanent_deletion_at,
    projectedAt: row.projected_at,
  } satisfies TrashRetentionTeamAttentionItem))
}
