import 'server-only'

import { getCurrentOrgId } from '@/lib/actions/org'
import type { Database } from '@/lib/supabase/database.types'
import { createClient } from '@/lib/supabase/server'

type TrashContextRow = Database['public']['Functions']['get_exact_resource_trash_context']['Returns'][number]

export type ExactResourceTrashContext = {
  state: 'trash'
  membershipId: string
  cause: 'direct' | 'inherited'
  parentMembershipId: string | null
  operationId: string
  rootResourceId: string
  rootResourceType: 'client' | 'matter' | 'document'
  operationState: Database['public']['Enums']['trash_operation_state']
  trashedAt: string
  trashedBy: string | null
  retention: {
    mode: 'manual_only' | 'retention_period'
    days: number | null
    purgeEligibleAt: string | null
    autoPurgeEnabled: boolean
    autoPurgeAt: string | null
    purgeScheduledAt: string | null
    blockerCount: number
  }
  // Display guidance for a later restore UI; never mutation authority.
  canRestore: boolean
}

export type ExactResourceRead<Record> =
  | { state: 'active'; record: Record }
  | { state: 'trash'; context: ExactResourceTrashContext }
  | null

function toTrashContext(row: TrashContextRow): ExactResourceTrashContext {
  return {
    state: 'trash',
    membershipId: row.membership_id,
    cause: row.cause,
    parentMembershipId: row.parent_membership_id,
    operationId: row.operation_id,
    rootResourceId: row.root_resource_id,
    rootResourceType: row.root_resource_type,
    operationState: row.operation_state,
    trashedAt: row.trashed_at,
    trashedBy: row.trashed_by,
    retention: {
      mode: row.retention_mode,
      days: row.retention_days,
      purgeEligibleAt: row.purge_eligible_at,
      autoPurgeEnabled: row.auto_purge_enabled,
      autoPurgeAt: row.auto_purge_at,
      purgeScheduledAt: row.purge_scheduled_at,
      blockerCount: row.blocker_count,
    },
    canRestore: row.can_restore,
  }
}

async function getTrashContext(
  resourceType: 'client' | 'matter' | 'document',
  resourceId: string,
  expectedMatterId: string | null,
): Promise<ExactResourceTrashContext | null> {
  const supabase = await createClient()
  const { data } = await supabase.rpc('get_exact_resource_trash_context', {
    p_resource_type: resourceType,
    p_resource_id: resourceId,
    p_expected_matter_id: expectedMatterId,
  })

  const context = data?.[0]
  return context ? toTrashContext(context) : null
}

export async function getExactClient(id: string): Promise<ExactResourceRead<Database['public']['Tables']['clients']['Row']>> {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return null

  const { data } = await supabase
    .from('clients')
    .select('*')
    .eq('id', id)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()

  if (data) return { state: 'active', record: data }
  const context = await getTrashContext('client', id, null)
  return context ? { state: 'trash', context } : null
}

export async function getExactMatter(id: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return null

  const { data } = await supabase
    .from('matters')
    .select('*, clients(id, name, gstin, pan)')
    .eq('id', id)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()

  if (data) return { state: 'active' as const, record: data }
  const context = await getTrashContext('matter', id, null)
  return context ? { state: 'trash' as const, context } : null
}

export async function getExactDocument(matterId: string, documentId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return null

  const { data } = await supabase
    .from('documents')
    .select('*, matters(id, title)')
    .eq('id', documentId)
    .eq('matter_id', matterId)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()

  if (data) return { state: 'active' as const, record: data }
  const context = await getTrashContext('document', documentId, matterId)
  return context ? { state: 'trash' as const, context } : null
}
