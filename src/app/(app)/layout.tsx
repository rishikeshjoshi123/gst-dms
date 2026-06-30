import { redirect } from 'next/navigation'
import { cookies } from 'next/headers'
import { Scale } from 'lucide-react'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { SidebarNav, SearchTrigger } from '@/components/nav/SidebarNav'
import { UserMenu } from '@/components/nav/UserMenu'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Dashboard',
}

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  // Get cookie-stored current org id
  const cookieStore = await cookies()
  const currentOrgId = cookieStore.get('current_org_id')?.value

  // Get all user's orgs
  const { data: memberships } = await supabase
    .from('org_members')
    .select('role, organisations(id, name)')
    .eq('user_id', user.id)

  const orgs = (memberships ?? []).map((m) => ({
    id: (m.organisations as { id: string; name: string }).id,
    name: (m.organisations as { id: string; name: string }).name,
    role: m.role,
  }))

  if (orgs.length === 0) redirect('/onboarding')

  const activeOrg = orgs.find(o => o.id === currentOrgId) ?? orgs[0]

  // If no org cookie set, set it now
  if (!currentOrgId) {
    cookieStore.set('current_org_id', activeOrg.id, {
      httpOnly: false,
      path: '/',
      maxAge: 60 * 60 * 24 * 365,
    })
  }

  const userMeta = {
    email: user.email ?? '',
    fullName: user.user_metadata?.full_name ?? '',
    avatarUrl: user.user_metadata?.avatar_url ?? null,
  }

  return (
    <div className="flex h-screen w-full overflow-hidden">
      {/* ── Sidebar ─────────────────────────────────────────────── */}
      <aside className="sidebar flex flex-col shrink-0 overflow-y-auto">
        {/* Logo */}
        <Link
          href="/dashboard"
          className="flex items-center gap-2.5 px-4 h-14 border-b border-[--border-subtle] shrink-0"
        >
          <div className="flex h-7 w-7 items-center justify-center rounded-[--radius-sm] bg-[--accent]">
            <Scale size={14} className="text-white" />
          </div>
          <span className="text-sm font-bold text-[--text-primary]">GST DMS</span>
        </Link>

        {/* Search */}
        <div className="px-3 pt-3">
          <SearchTrigger orgId={activeOrg.id} />
        </div>

        {/* Org header */}
        <div className="px-3 pt-4 pb-2">
          <p className="text-[11px] font-semibold uppercase tracking-wider text-[--text-muted] px-3 mb-1">
            {activeOrg.name}
          </p>

          {/* Navigation items */}
          <SidebarNav />
        </div>

        {/* Push user to bottom */}
        <div className="mt-auto px-3 pb-3 border-t border-[--border-subtle] pt-3">
          <UserMenu
            user={userMeta}
            currentOrg={activeOrg}
            allOrgs={orgs}
          />
        </div>
      </aside>

      {/* ── Main content ─────────────────────────────────────────── */}
      <main className="flex-1 overflow-y-auto bg-[--bg-base]">
        {children}
      </main>
    </div>
  )
}
