import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getStagedDocumentCount } from '@/lib/actions/inbox'
import { getUnreadNotificationCount } from '@/lib/actions/notifications'
import { getCurrentOrgId } from '@/lib/actions/org'
import { SidebarNav } from '@/components/nav/SidebarNav'
import { UserMenu } from '@/components/nav/UserMenu'
import { ThemeToggle } from '@/components/nav/ThemeToggle'
import { BreadcrumbProvider } from '@/components/nav/BreadcrumbContext'
import { BreadcrumbNav } from '@/components/nav/BreadcrumbNav'
import type { Metadata } from 'next'

export const dynamic = 'force-dynamic'
export const revalidate = 0

export const metadata: Metadata = {
  title: 'Dashboard',
}

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  // The cookie only remembers a selection; this returns it only after the
  // signed-in user's membership has been verified.
  const currentOrgId = await getCurrentOrgId()

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

  const [inboxCount, notifCount] = await Promise.all([
    getStagedDocumentCount(),
    getUnreadNotificationCount(),
  ])

  const userMeta = {
    email: user.email ?? '',
    fullName: user.user_metadata?.full_name ?? '',
    avatarUrl: user.user_metadata?.avatar_url ?? null,
  }

  return (
    <BreadcrumbProvider>
      <div className="flex h-screen w-full overflow-hidden bg-[var(--bg)] text-[var(--text-primary)] transition-colors duration-200">
        {/* ── Sidebar ─────────────────────────────────────────────── */}
        <div className="w-16 shrink-0 h-full relative z-20">
          <aside
            className="group absolute top-0 left-0 h-full flex flex-col overflow-x-hidden shadow-xl w-16 hover:w-60 transition-all duration-300 ease-in-out border-r border-stone-800"
            style={{ backgroundColor: 'var(--sidebar-bg)' }}
          >
          {/* Navigation items */}
          <div className="px-3 pt-6 pb-2 flex-1">
            <SidebarNav inboxCount={inboxCount} notifCount={notifCount} />
          </div>
          </aside>
        </div>

        {/* ── Main content wrapper ─────────────────────────────────────────── */}
        <div className="flex-1 flex flex-col overflow-hidden">
          {/* Topbar */}
          <header className="relative z-10 h-[48px] bg-[var(--surface)] border-b border-[var(--border)] flex items-center justify-between px-6 shrink-0 shadow-xs transition-colors duration-200">
            <BreadcrumbNav activeOrgName={activeOrg.name} />
            <div className="relative z-10 flex items-center gap-3.5 pointer-events-auto">
              <ThemeToggle />
              <UserMenu user={userMeta} currentOrg={activeOrg} allOrgs={orgs} />
            </div>
          </header>

          {/* Page Content */}
          <main className="flex-1 overflow-hidden flex flex-col p-6 max-w-7xl w-full mx-auto">
            {children}
          </main>
        </div>
      </div>
    </BreadcrumbProvider>
  )
}
