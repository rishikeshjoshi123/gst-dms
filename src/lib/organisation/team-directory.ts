import 'server-only'

import { createClient } from '@/lib/supabase/server'
import type { Database } from '@/lib/supabase/database.types'

type TeamDirectoryRow = Database['public']['Functions']['get_team_directory']['Returns'][number]
export type TeamDirectoryRole = Database['public']['Enums']['org_member_role']
export type TeamDirectoryState = Database['public']['Enums']['organisation_membership_state']

export type TeamDirectoryParams = {
  query?: string
  role?: TeamDirectoryRole
  state?: Extract<TeamDirectoryState, 'active' | 'suspended'>
  limit?: number
  offset?: number
}

export type TeamDirectoryEntry = TeamDirectoryRow & { membership_id: string; user_id: string; role: TeamDirectoryRole; state: Extract<TeamDirectoryState, 'active' | 'suspended'>; is_owner: boolean; joined_at: string; capabilities: string[] }

export type TeamDirectoryResult =
  | { ok: true; entries: TeamDirectoryEntry[]; total: number; limit: number; offset: number }
  | { ok: false; error: 'unavailable'; entries: []; total: 0; limit: number; offset: number }

const MAX_LIMIT = 100
const DEFAULT_LIMIT = 50

export function normalizeTeamDirectoryParams(params: TeamDirectoryParams = {}) {
  const limit = Number.isInteger(params.limit) && params.limit! > 0
    ? Math.min(params.limit!, MAX_LIMIT)
    : DEFAULT_LIMIT
  const offset = Number.isInteger(params.offset) && params.offset! >= 0
    ? Math.min(params.offset!, 10_000)
    : 0
  const query = params.query?.trim().slice(0, 120) || undefined
  const role = params.role === 'admin' || params.role === 'associate' || params.role === 'viewer' ? params.role : undefined
  const state = params.state === 'active' || params.state === 'suspended' ? params.state : undefined

  return { query, role, state, limit, offset }
}

function isMemberRow(row: TeamDirectoryRow): row is TeamDirectoryEntry {
  return row.outcome_code === 'ok' && row.membership_id !== null && row.user_id !== null && row.role !== null && row.state !== null && row.is_owner !== null && row.joined_at !== null && row.capabilities !== null
}

export async function getTeamDirectory(params: TeamDirectoryParams = {}): Promise<TeamDirectoryResult> {
  const normalized = normalizeTeamDirectoryParams(params)
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_team_directory', {
    p_query: normalized.query ?? null,
    p_role: normalized.role ?? null,
    p_state: normalized.state ?? null,
    p_limit: normalized.limit,
    p_offset: normalized.offset,
  })

  if (error) {
    console.error('Team directory error:', error)
    return { ok: false, error: 'unavailable', entries: [], total: 0, limit: normalized.limit, offset: normalized.offset }
  }

  const meta = data?.[0]
  if (!meta || meta.outcome_code !== 'ok') {
    return { ok: false, error: 'unavailable', entries: [], total: 0, limit: normalized.limit, offset: normalized.offset }
  }
  return {
    ok: true,
    entries: data.filter(isMemberRow),
    total: Number(meta.total_count),
    limit: normalized.limit,
    offset: meta.page_offset,
  }
}
