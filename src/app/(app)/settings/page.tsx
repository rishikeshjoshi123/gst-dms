import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { SettingsClient } from './SettingsClient'
import type { Metadata } from 'next'
import { getCurrentOrgId } from '@/lib/actions/org'

export const metadata: Metadata = { title: 'Settings' }

export default async function SettingsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const orgId = await getCurrentOrgId()
  if (!orgId) redirect('/onboarding')

  // Fetch org details
  const { data: org } = await supabase
    .from('organisations')
    .select('id, name, created_by')
    .eq('id', orgId)
    .single()

  if (!org) redirect('/onboarding')

  const { data: memberRows } = await (supabase.rpc as any)('get_my_team_members')
  const members = (memberRows ?? []).map((m: any) => ({ membership_id: m.membership_id, role: m.role as 'admin' | 'associate' | 'viewer', email: m.authorised_email ?? null, full_name: m.display_name ?? null, professional_title: m.professional_title ?? null, is_owner: m.is_owner, state: m.state, joined_at: m.joined_at }))

  const { data: contexts } = await (supabase.rpc as any)('get_my_organisation_context')
  const currentContext = (contexts ?? []).find((context: any) => context.org_id === orgId)
  const currentUserRole = currentContext?.role ?? 'member'
  const capabilities = currentContext?.capabilities ?? []

  // Invite addresses are administrative data; do not even fetch them for a
  // non-admin and rely on RLS as a second line of defense.
  const { data: pendingInvites } = (capabilities.includes('team.invite.standard') || capabilities.includes('team.invite.admin'))
    ? await (supabase.rpc as any)('get_organisation_invites')
    : { data: [] }

  return (
    <SettingsClient
      orgId={orgId}
      orgName={org.name}
      currentMembershipId={(contexts ?? []).find((context: any) => context.org_id === orgId)?.membership_id ?? ''}
      currentUserRole={currentUserRole}
      capabilities={capabilities}
      members={members}
      pendingInvites={(pendingInvites ?? []).map((i: any) => ({
        id: i.id,
        invited_email: i.authorized_email,
        role: i.role as 'admin' | 'associate' | 'viewer',
        status: i.state,
        expires_at: i.expires_at,
      }))}
    />
  )
}
