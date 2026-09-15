import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getStagedDocumentCount } from '@/lib/actions/inbox'
import { getUnreadNotificationCount } from '@/lib/actions/notifications'
import { SidebarNav } from '@/components/nav/SidebarNav'
import { UserMenu } from '@/components/nav/UserMenu'
import { ThemeToggle } from '@/components/nav/ThemeToggle'
import { BreadcrumbProvider } from '@/components/nav/BreadcrumbContext'
import { BreadcrumbNav } from '@/components/nav/BreadcrumbNav'
import { MobileNavDrawer } from '@/components/nav/MobileNavDrawer'
import type { Metadata } from 'next'
import { isLegacyUsageDevelopmentEnvironment } from '@/lib/platform/legacy-usage-boundary'

export const dynamic = 'force-dynamic'
export const revalidate = 0

export const metadata: Metadata = {
  title: 'Dashboard',
}

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  // One central shell gate rechecks the canonical lifecycle on every protected
  // request. A still-valid Auth session is not organisation access.
  const { data: contexts } = await supabase.rpc('get_my_organisation_context')
  const activeContexts = (contexts ?? []).filter((context) => context.state === 'active')
  if (activeContexts.length !== 1 || (contexts ?? []).length !== 1) redirect('/onboarding')
  const context = activeContexts[0]
  const { data: organisation } = await supabase.from('organisations').select('id,name').eq('id', context.org_id).maybeSingle()
  if (!organisation) redirect('/onboarding')
  const activeOrg = { id: organisation.id, name: organisation.name, role: context.role }
  const orgs = [activeOrg]

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
        <div className="hidden md:block relative z-20 h-full w-16 shrink-0">
          <aside
            className="group/sidebar absolute inset-y-0 left-0 z-30 flex h-full w-16 flex-col overflow-hidden border-r border-[var(--sidebar-border,var(--border))] transition-[width,box-shadow] duration-200 ease-out hover:w-56 focus-within:w-56 hover:shadow-xl focus-within:shadow-xl"
            style={{ backgroundColor: 'var(--sidebar-bg)' }}
          >
          <div className="hidden h-14 shrink-0 items-center border-b border-[var(--sidebar-border,var(--border))] px-4 md:flex">
            <span className="hidden whitespace-nowrap text-sm font-semibold tracking-wide text-[var(--on-sidebar,var(--sidebar-accent))] opacity-0 transition-opacity duration-150 md:block group-hover/sidebar:opacity-100 group-focus-within/sidebar:opacity-100">CaseChain</span>
          </div>
          {/* Navigation items */}
          <div className="flex-1 px-2 py-4 md:px-3">
            <SidebarNav
              inboxCount={inboxCount}
              notifCount={notifCount}
              showDevelopmentUsage={isLegacyUsageDevelopmentEnvironment()}
            />
          </div>
          </aside>
        </div>

        {/* ── Main content wrapper ─────────────────────────────────────────── */}
        <div className="flex-1 flex flex-col overflow-hidden">
          {/* Topbar */}
          <header className="relative z-10 flex h-14 shrink-0 items-center justify-between border-b border-[var(--border)] bg-[var(--surface)] px-4 transition-colors duration-200 md:px-6">
            <div className="flex items-center gap-2">
              <MobileNavDrawer
                inboxCount={inboxCount}
                notifCount={notifCount}
                showDevelopmentUsage={isLegacyUsageDevelopmentEnvironment()}
              />
              <BreadcrumbNav />
            </div>
            <div className="relative z-10 flex items-center gap-3.5 pointer-events-auto">
              <ThemeToggle />
              <UserMenu user={userMeta} currentOrg={activeOrg} allOrgs={orgs} />
            </div>
          </header>

          {/* Page Content */}
          <main className="mx-auto flex w-full max-w-7xl flex-1 flex-col overflow-hidden p-3 sm:p-4 md:p-6">
            {children}
          </main>
        </div>
      </div>
    </BreadcrumbProvider>
  )
}
