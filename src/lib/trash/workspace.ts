import 'server-only'

import { getCurrentOrgId } from '@/lib/actions/org'
import type { Database } from '@/lib/supabase/database.types'
import { createClient } from '@/lib/supabase/server'
import {
  shapeTrashWorkspaceRows,
  type TrashResourceFilter,
  type TrashWorkspaceData,
  type TrashWorkspaceProjectionRow,
} from './workspace-model'
import type { TrashRestorePreflight } from './restore-model'

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
  const [{ data, error }, { data: authData }] = await Promise.all([
    supabase.rpc('get_trash_workspace', {
      p_org_id: orgId,
      p_query: query.query || undefined,
      p_resource_type: query.resourceType === 'all' ? undefined : query.resourceType,
      p_selected_operation_id: query.selectedOperationId ?? undefined,
      p_limit: 50,
    }),
    supabase.auth.getUser(),
  ])
  if (error) throw new TrashWorkspaceReadError()

  let timeZone = 'Asia/Kolkata'
  const userId = authData.user?.id
  if (userId) {
    const { data: profile } = await supabase
      .from('user_profiles')
      .select('timezone')
      .eq('user_id', userId)
      .maybeSingle()
    if (profile?.timezone) timeZone = profile.timezone
  }

  const shaped = shapeTrashWorkspaceRows(data as (TrashWorkspaceRow & TrashWorkspaceProjectionRow)[], query.selectedOperationId)
  if (shaped.selectedOperation) {
    const { data: preflightRows } = await supabase.rpc('get_trash_restore_preflight', {
      p_operation_id: shaped.selectedOperation.id,
    })
    const preflight = preflightRows?.[0]
    if (preflight) {
      shaped.selectedOperation.restorePreflight = {
        status: preflight.code as TrashRestorePreflight['status'],
        canRestore: preflight.can_restore,
        blockerCode: preflight.blocker_code,
        blockingOperationId: preflight.blocking_operation_id,
      }
    }
  }

  return {
    ...shaped,
    timeZone,
  }
}
