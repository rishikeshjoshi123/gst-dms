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
  Activity,
  Trash2,
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
  { href: '/trash',         icon: Trash2,   label: 'Trash' },
  { href: '/settings',      icon: Settings, label: 'Settings' },
]

export function SidebarNav({ inboxCount = 0, notifCount = 0, isMobile = false }: { inboxCount?: number; notifCount?: number; isMobile?: boolean }) {
  const pathname = usePathname()

  return (
    <nav className="flex flex-col gap-1">
      {navItems.map(({ href, icon: Icon, label }) => (
        <Link
          key={href}
          href={href}
          className={cn('nav-item min-h-10', isMobile ? 'justify-start' : 'justify-center md:justify-start', pathname.startsWith(href) && 'active')}
          title={label}
        >
          <Icon size={16} className="nav-icon shrink-0" />
          <span className={cn(
            "flex-1 whitespace-nowrap transition-opacity duration-150",
            isMobile
              ? "block opacity-100"
              : "hidden opacity-0 md:block md:group-hover/sidebar:opacity-100 md:group-focus-within/sidebar:opacity-100"
          )}>
            {label}
          </span>
          {href === '/inbox' && inboxCount > 0 && (
            <span className={cn(
              "h-5 min-w-8 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-accent)] px-2 text-[10px] font-semibold text-[var(--sidebar-bg)] transition-opacity duration-150",
              isMobile
                ? "flex opacity-100"
                : "hidden opacity-0 md:flex md:group-hover/sidebar:opacity-100 md:group-focus-within/sidebar:opacity-100"
            )}>
              {inboxCount > 99 ? '99+' : inboxCount}
            </span>
          )}
        </Link>
      ))}

      <div className="my-2 h-px bg-[var(--sidebar-border,var(--border))]" />

      {bottomItems.map(({ href, icon: Icon, label, badgeKey }) => {
        const count = badgeKey === 'notif' ? notifCount : 0
        return (
          <Link
            key={href}
            href={href}
            className={cn('nav-item relative min-h-10', isMobile ? 'justify-start' : 'justify-center md:justify-start', pathname.startsWith(href) && 'active')}
            title={label}
          >
            <div className="relative shrink-0">
              <Icon size={16} className="nav-icon" />
              {!isMobile && count > 0 && (
                <span className="absolute -right-1 -top-1 flex h-3.5 w-3.5 items-center justify-center rounded-full bg-[var(--danger)] text-[8px] font-semibold text-[var(--on-danger)] md:hidden">
                  {count > 9 ? '9+' : count}
                </span>
              )}
            </div>
            <span className={cn(
              "whitespace-nowrap transition-opacity duration-150",
              isMobile
                ? "block opacity-100"
                : "hidden opacity-0 md:block md:group-hover/sidebar:opacity-100 md:group-focus-within/sidebar:opacity-100"
            )}>
              {label}
            </span>
            {count > 0 && (
              <span className={cn(
                "ml-auto h-5 min-w-8 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--danger)] px-2 text-[10px] font-semibold text-[var(--on-danger)] transition-opacity duration-150",
                isMobile
                  ? "flex opacity-100"
                  : "hidden opacity-0 md:flex md:group-hover/sidebar:opacity-100 md:group-focus-within/sidebar:opacity-100"
              )}>
                {count > 99 ? '99+' : count}
              </span>
            )}
          </Link>
        )
      })}
    </nav>
  )
}
