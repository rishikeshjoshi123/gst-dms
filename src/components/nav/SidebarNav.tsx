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
} from 'lucide-react'
import { cn } from '@/lib/utils'

const navItems = [
  { href: '/dashboard', icon: LayoutDashboard, label: 'Dashboard' },
  { href: '/inbox',     icon: InboxIcon,       label: 'Document Hub' },
  { href: '/clients',   icon: Users,           label: 'Clients' },
  { href: '/matters',   icon: FolderOpen,       label: 'Matters' },
]

const bottomItems = [
  { href: '/notifications', icon: Bell,   label: 'Notifications' },
  { href: '/settings',      icon: Settings, label: 'Settings' },
]

export function SidebarNav({ inboxCount = 0 }: { inboxCount?: number }) {
  const pathname = usePathname()

  return (
    <nav className="flex flex-col gap-1">
      {navItems.map(({ href, icon: Icon, label }) => (
        <Link
          key={href}
          href={href}
          className={cn(
            'nav-item',
            pathname.startsWith(href) && 'active'
          )}
        >
          <Icon size={16} className="nav-icon shrink-0" />
          <span className="flex-1 whitespace-nowrap overflow-hidden opacity-0 group-hover:opacity-100 transition-opacity duration-300">{label}</span>
          {href === '/inbox' && inboxCount > 0 && (
            <span className="flex h-5 items-center justify-center rounded-full bg-[var(--accent)] px-2 text-[10px] font-bold text-white shrink-0 opacity-0 group-hover:opacity-100 transition-opacity duration-300">
              {inboxCount > 99 ? '99+' : inboxCount}
            </span>
          )}
        </Link>
      ))}

      <div className="my-2 h-px bg-[var(--border-subtle)]" />

      {bottomItems.map(({ href, icon: Icon, label }) => (
        <Link
          key={href}
          href={href}
          className={cn(
            'nav-item',
            pathname.startsWith(href) && 'active'
          )}
        >
          <Icon size={16} className="nav-icon shrink-0" />
          <span className="whitespace-nowrap overflow-hidden opacity-0 group-hover:opacity-100 transition-opacity duration-300">{label}</span>
        </Link>
      ))}
    </nav>
  )
}

