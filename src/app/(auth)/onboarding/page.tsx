import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { OnboardingClient } from './OnboardingClient'
import { signOut } from '@/lib/actions/auth'
import { Button } from '@/components/ui/button'

export const dynamic = 'force-dynamic'
export const revalidate = 0

export default async function OnboardingPage({
  searchParams,
}: {
  searchParams: Promise<{ invite_error?: string | string[] }>
}) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: contexts } = await supabase.rpc('get_my_organisation_context')
  const contextRows = contexts ?? []
  const current = contextRows.length === 1 ? contextRows[0] : undefined
  if (current?.state === 'active') redirect('/dashboard')
  if (current?.state === 'suspended' || contextRows.length > 1) {
    return (
      <section aria-labelledby="suspended-heading" className="space-y-5">
        <div>
          <h1 id="suspended-heading" className="text-2xl font-bold text-[var(--text-primary)]">Access suspended</h1>
          <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">
            {current?.state === 'suspended' ? 'Your organisation access is suspended.' : 'Your organisation access is unavailable.'} Contact an organisation administrator for help.
          </p>
        </div>
        <form action={signOut}><Button type="submit" variant="outline" size="lg">Log out</Button></form>
      </section>
    )
  }
  if (!user.email_confirmed_at) {
    return (
      <section aria-labelledby="verify-heading" className="space-y-5">
        <div>
          <h1 id="verify-heading" className="text-2xl font-bold text-[var(--text-primary)]">Verify your email</h1>
          <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">
            Open the verification link in your email before creating or joining an organisation.
          </p>
        </div>
        <form action={signOut}><Button type="submit" variant="outline" size="lg">Log out</Button></form>
      </section>
    )
  }

  const [{ data: pending }, params] = await Promise.all([
    supabase.rpc('get_my_pending_organisation_invites'),
    searchParams,
  ])
  const invites = (pending ?? []).map((invite) => ({
    id: invite.id,
    role: invite.role,
    orgName: invite.org_name,
  }))
  return <OnboardingClient invites={invites} invalidInvite={params.invite_error === 'invalid_invitation'} />
}
