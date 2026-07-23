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
          className={cn('nav-item group', pathname.startsWith(href) && 'active')}
        >
          <Icon size={16} className="nav-icon shrink-0" />
          <span className="flex-1 whitespace-nowrap overflow-hidden opacity-0 group-hover:opacity-100 transition-opacity duration-300">
            {label}
          </span>
          {href === '/inbox' && inboxCount > 0 && (
            <span className="flex h-5 items-center justify-center rounded-full bg-blue-500 px-2 text-[10px] font-bold text-white shrink-0 opacity-0 group-hover:opacity-100 transition-opacity duration-300">
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
            className={cn('nav-item group relative', pathname.startsWith(href) && 'active')}
          >
            <div className="relative shrink-0">
              <Icon size={16} className="nav-icon" />
              {count > 0 && (
                <span className="absolute -top-1 -right-1 flex h-3.5 w-3.5 items-center justify-center rounded-full bg-red-500 text-[8px] font-bold text-white">
                  {count > 9 ? '9+' : count}
                </span>
              )}
            </div>
            <span className="whitespace-nowrap overflow-hidden opacity-0 group-hover:opacity-100 transition-opacity duration-300">
              {label}
            </span>
            {count > 0 && (
              <span className="ml-auto flex h-5 items-center justify-center rounded-full bg-red-500 px-2 text-[10px] font-bold text-white shrink-0 opacity-0 group-hover:opacity-100 transition-opacity duration-300">
                {count > 99 ? '99+' : count}
              </span>
            )}
          </Link>
        )
      })}
    </nav>
  )
}
