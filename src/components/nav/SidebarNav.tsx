'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import {
  LayoutDashboard,
  Users,
  FolderOpen,
  Inbox as InboxIcon,
  Settings,
  Bell,
  StickyNote,
  Activity
} from 'lucide-react'
import { cn } from '@/lib/utils'

const navItems = [
  { href: '/dashboard', icon: LayoutDashboard, label: 'Dashboard' },
  { href: '/inbox',     icon: InboxIcon,       label: 'Document Hub' },
  { href: '/clients',   icon: Users,           label: 'Clients' },
  { href: '/matters',   icon: FolderOpen,      label: 'Matters' },
  { href: '/notes',     icon: StickyNote,      label: 'Notes' },
]

const bottomItems = [
  { href: '/usage',         icon: Activity, label: 'Usage' },
  { href: '/notifications', icon: Bell,     label: 'Notifications', badgeKey: 'notif' },
  { href: '/settings',      icon: Settings, label: 'Settings' },
]

export function SidebarNav({ inboxCount = 0, notifCount = 0 }: { inboxCount?: number; notifCount?: number }) {
  const pathname = usePathname()

  return (
    <nav className="flex flex-col gap-1">
      {navItems.map(({ href, icon: Icon, label }) => (
        <Link
          key={href}
          href={href}
          className={cn('nav-item min-h-10 justify-center md:justify-start', pathname.startsWith(href) && 'active')}
          title={label}
        >
          <Icon size={16} className="nav-icon shrink-0" />
          <span className="hidden flex-1 whitespace-nowrap opacity-0 transition-opacity duration-150 md:block md:group-hover/sidebar:opacity-100 md:group-focus-within/sidebar:opacity-100">
            {label}
          </span>
          {href === '/inbox' && inboxCount > 0 && (
            <span className="hidden h-5 min-w-8 shrink-0 items-center justify-center rounded-full bg-[var(--sidebar-accent)] px-2 text-[10px] font-semibold text-[var(--sidebar-bg)] opacity-0 transition-opacity duration-150 md:flex md:group-hover/sidebar:opacity-100 md:group-focus-within/sidebar:opacity-100">
              {inboxCount > 99 ? '99+' : inboxCount}
            </span>
          )}
        </Link>
      ))}

      <div className="my-2 h-px bg-white/10" />

      {bottomItems.map(({ href, icon: Icon, label, badgeKey }) => {
        const count = badgeKey === 'notif' ? notifCount : 0
        return (
          <Link
            key={href}
            href={href}
            className={cn('nav-item relative min-h-10 justify-center md:justify-start', pathname.startsWith(href) && 'active')}
            title={label}
          >
            <div className="relative shrink-0">
              <Icon size={16} className="nav-icon" />
              {count > 0 && (
                <span className="absolute -right-1 -top-1 flex h-3.5 w-3.5 items-center justify-center rounded-full bg-[var(--danger)] text-[8px] font-semibold text-white md:hidden">
                  {count > 9 ? '9+' : count}
                </span>
              )}
            </div>
            <span className="hidden whitespace-nowrap opacity-0 transition-opacity duration-150 md:block md:group-hover/sidebar:opacity-100 md:group-focus-within/sidebar:opacity-100">
              {label}
            </span>
            {count > 0 && (
              <span className="ml-auto hidden h-5 min-w-8 shrink-0 items-center justify-center rounded-full bg-[var(--danger)] px-2 text-[10px] font-semibold text-white opacity-0 transition-opacity duration-150 md:flex md:group-hover/sidebar:opacity-100 md:group-focus-within/sidebar:opacity-100">
                {count > 99 ? '99+' : count}
              </span>
            )}
          </Link>
        )
      })}
    </nav>
  )
}
