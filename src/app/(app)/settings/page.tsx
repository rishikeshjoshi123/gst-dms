import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { SettingsClient } from './SettingsClient'
import type { Metadata } from 'next'
import { getCurrentOrgId } from '@/lib/actions/org'
import { getOrganisationTrashRetentionPolicy } from '@/lib/trash/retention-policy'
import type { Database } from '@/lib/supabase/database.types'

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

  const retentionPolicyResult = await getOrganisationTrashRetentionPolicy(orgId)

  const { data: contexts } = await supabase.rpc('get_my_organisation_context')
  const currentContext = (contexts ?? []).find((context) => context.org_id === orgId)
  const capabilities = currentContext?.capabilities ?? []

  // Invite addresses are administrative data; do not even fetch them for a
  // non-admin and rely on RLS as a second line of defense.
  const { data: pendingInvites } = (capabilities.includes('team.invite.standard') || capabilities.includes('team.invite.admin'))
    ? await supabase.rpc('get_organisation_invites')
    : { data: [] }

  return (
    <SettingsClient
      orgName={org.name}
      capabilities={capabilities}
      pendingInvites={(pendingInvites ?? []).map((i) => ({
        id: i.id,
        invited_email: i.authorized_email,
        role: i.role as Database['public']['Enums']['org_member_role'],
        status: i.state,
        expires_at: i.expires_at,
      }))}
      retentionPolicy={retentionPolicyResult.policy}
      retentionPolicyLoadError={retentionPolicyResult.error}
    />
  )
}
