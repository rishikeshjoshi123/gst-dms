import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { SettingsClient } from './SettingsClient'
import type { Metadata } from 'next'
import { getCurrentOrgId } from '@/lib/actions/org'
import { getOrganisationTrashRetentionPolicy } from '@/lib/trash/retention-policy'

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

  return (
    <SettingsClient
      orgName={org.name}
      retentionPolicy={retentionPolicyResult.policy}
      retentionPolicyLoadError={retentionPolicyResult.error}
    />
  )
}
