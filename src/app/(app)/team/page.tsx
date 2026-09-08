import type { Metadata } from 'next'

import { getTeamDirectory, normalizeTeamDirectoryParams, type TeamDirectoryParams } from '@/lib/organisation/team-directory'
import { TeamWorkspace } from './TeamWorkspace'

export const metadata: Metadata = { title: 'Team' }

type TeamPageProps = {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}

function value(params: Record<string, string | string[] | undefined>, key: string) {
  return typeof params[key] === 'string' ? params[key] : undefined
}

export default async function TeamPage({ searchParams }: TeamPageProps) {
  const params = await searchParams
  const page = Number(value(params, 'page'))
  const rawRole = value(params, 'role')
  const rawState = value(params, 'state')
  const query: TeamDirectoryParams = {
    query: value(params, 'q'),
    role: rawRole === 'admin' || rawRole === 'associate' || rawRole === 'viewer' ? rawRole : undefined,
    state: rawState === 'active' || rawState === 'suspended' ? rawState : undefined,
    limit: 50,
    offset: Number.isInteger(page) && page > 1 ? (page - 1) * 50 : 0,
  }
  const normalizedQuery = normalizeTeamDirectoryParams(query)
  const result = await getTeamDirectory(normalizedQuery)

  return <TeamWorkspace result={result} initialQuery={normalizedQuery} selectedMembershipId={value(params, 'member')} />
}
