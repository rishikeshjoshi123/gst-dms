import 'server-only'

import { getCurrentOrgId } from '@/lib/actions/org'
import type { Database } from '@/lib/supabase/database.types'
import { createClient } from '@/lib/supabase/server'
import {
  shapeTrashWorkspaceRows,
  type TrashOperation,
  type TrashResourceFilter,
  type TrashWorkspaceData,
  type TrashWorkspaceProjectionRow,
} from './workspace-model'
import type { TrashRestorePreflight } from './restore-model'
import { shapeTrashPurgeImpact } from './purge-model'

type TrashWorkspaceRow = Database['public']['Functions']['get_trash_workspace']['Returns'][number]

export type TrashWorkspaceQuery = {
  query: string
  resourceType: TrashResourceFilter
  selectedOperationId: string | null
}

export class TrashWorkspaceReadError extends Error {
  constructor() {
    super('Trash workspace could not be loaded')
    this.name = 'TrashWorkspaceReadError'
  }
}

export async function getTrashWorkspace(query: TrashWorkspaceQuery): Promise<TrashWorkspaceData> {
  const orgId = await getCurrentOrgId()
  if (!orgId) return { operations: [], selectedOperation: null, totalStorageBytes: 0, timeZone: 'Asia/Kolkata' }

  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_trash_workspace', {
    p_org_id: orgId,
    p_query: query.query || undefined,
    p_resource_type: query.resourceType === 'all' ? undefined : query.resourceType,
    p_selected_operation_id: query.selectedOperationId ?? undefined,
    p_limit: 50,
  })
  if (error) throw new TrashWorkspaceReadError()

  const shaped = shapeTrashWorkspaceRows(data as (TrashWorkspaceRow & TrashWorkspaceProjectionRow)[], query.selectedOperationId)
  if (shaped.operations.length > 0) {
    const { data: retentionRows, error: retentionError } = await supabase.rpc('get_trash_workspace_retention', {
      p_org_id: orgId,
      p_operation_ids: shaped.operations.map((operation) => operation.id),
    })
    if (retentionError) throw new TrashWorkspaceReadError()
    const retentionByOperation = new Map((retentionRows ?? []).map((row) => [row.operation_id, row]))
    for (const operation of shaped.operations) {
      const retention = retentionByOperation.get(operation.id)
      if (!retention) continue
      operation.autoPurgeAt = retention.auto_purge_at
      operation.remainingSeconds = retention.remaining_seconds === null ? null : Number(retention.remaining_seconds)
      operation.retentionBlockerCount = retention.blocker_count
      operation.retentionStatus = retention.retention_status as TrashOperation['retentionStatus']
    }
  }
  if (shaped.selectedOperation) {
    const [{ data: preflightRows }, { data: impactRows }] = await Promise.all([
      supabase.rpc('get_trash_restore_preflight', { p_operation_id: shaped.selectedOperation.id }),
      supabase.rpc('get_trash_purge_impact', { p_operation_id: shaped.selectedOperation.id }),
    ])
    const preflight = preflightRows?.[0]
    if (preflight) {
      shaped.selectedOperation.restorePreflight = {
        status: preflight.code as TrashRestorePreflight['status'],
        canRestore: preflight.can_restore,
        blockerCode: preflight.blocker_code,
        blockingOperationId: preflight.blocking_operation_id,
      }
    }
    const impact = (impactRows as unknown as Array<Record<string, unknown>> | null)?.[0]
    if (impact) shaped.selectedOperation.purgeImpact = shapeTrashPurgeImpact(impact)
  }

  return {
    ...shaped,
    timeZone: 'Asia/Kolkata',
  }
}
