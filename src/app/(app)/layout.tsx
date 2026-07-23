import { redirect } from 'next/navigation'
import { cookies } from 'next/headers'
import { Scale } from 'lucide-react'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { getStagedDocumentCount } from '@/lib/actions/inbox'
import { getUnreadNotificationCount } from '@/lib/actions/notifications'
import { SidebarNav } from '@/components/nav/SidebarNav'
import { UserMenu } from '@/components/nav/UserMenu'
import { BreadcrumbProvider } from '@/components/nav/BreadcrumbContext'
import { BreadcrumbNav } from '@/components/nav/BreadcrumbNav'
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

  const [inboxCount, notifCount] = await Promise.all([
    getStagedDocumentCount(),
    getUnreadNotificationCount(),
  ])

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
          <header className="h-[48px] bg-[var(--surface)] border-b border-[var(--border)] flex items-center justify-between px-6 shrink-0 shadow-xs z-10 transition-colors duration-200">
            <BreadcrumbNav activeOrgName={activeOrg.name} />
            <UserMenu user={userMeta} currentOrg={activeOrg} allOrgs={orgs} />
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
