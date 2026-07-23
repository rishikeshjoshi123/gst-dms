import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { cookies } from 'next/headers'

import { LandingPage } from './LandingPage'

export default async function RootPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) return <LandingPage />

  // Check if user has an org
  const cookieStore = await cookies()
  const orgId = cookieStore.get('current_org_id')?.value

  if (orgId) redirect('/dashboard')

  // No org cookie — check DB
  const { data: membership } = await supabase
    .from('org_members')
    .select('org_id')
    .eq('user_id', user.id)
    .limit(1)
    .single()

  if (membership) redirect('/dashboard')

  redirect('/onboarding')
}
