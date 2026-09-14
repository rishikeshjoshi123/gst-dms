import type { Metadata } from 'next'

import { getTeamDirectory, normalizeTeamDirectoryParams, type TeamDirectoryParams } from '@/lib/organisation/team-directory'
import { createClient } from '@/lib/supabase/server'
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
  const [result, supabase] = await Promise.all([getTeamDirectory(normalizedQuery), createClient()])
  const { data: contexts } = await supabase.rpc('get_my_organisation_context')
  const activeContexts = (contexts ?? []).filter((context) => context.state === 'active')
  const activeContext = activeContexts.length === 1 ? activeContexts[0] : undefined
  const capabilities = activeContext?.capabilities ?? []
  const canAdministerInvitations = capabilities.includes('team.invite.standard')
  const rawInvitationState = value(params, 'invite_state')
  const invitationState = ['pending', 'accepted', 'rejected', 'expired', 'revoked', 'superseded', 'all'].includes(rawInvitationState ?? '') ? rawInvitationState! : 'pending'
  const { data: invitations } = canAdministerInvitations
    ? await supabase.rpc('get_organisation_invites', { p_state: invitationState })
    : { data: [] }

  const requestedView = value(params, 'view') === 'invitations' ? 'invitations' : 'members'
  const view = requestedView === 'invitations' && !canAdministerInvitations ? 'members' : requestedView

  return <TeamWorkspace
    result={result}
    initialQuery={normalizedQuery}
    selectedMembershipId={value(params, 'member')}
    view={view}
    invitationState={invitationState}
    invitations={invitations ?? []}
    capabilities={capabilities}
  />
}
