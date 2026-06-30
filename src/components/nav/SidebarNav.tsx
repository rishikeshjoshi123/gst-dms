'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import {
  LayoutDashboard,
  Users,
  FolderOpen,
  Settings,
  Bell,
  Search,
} from 'lucide-react'
import { cn } from '@/lib/utils'

const navItems = [
  { href: '/dashboard', icon: LayoutDashboard, label: 'Dashboard' },
  { href: '/clients',   icon: Users,           label: 'Clients' },
  { href: '/matters',   icon: FolderOpen,       label: 'Matters' },
]

const bottomItems = [
  { href: '/notifications', icon: Bell,   label: 'Notifications' },
  { href: '/settings',      icon: Settings, label: 'Settings' },
]

export function SidebarNav() {
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
          <span>{label}</span>
        </Link>
      ))}

      <div className="my-2 h-px bg-[--border-subtle]" />

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
          <span>{label}</span>
        </Link>
      ))}
    </nav>
  )
}

export function SearchTrigger({ orgId }: { orgId: string }) {
  return (
    <button
      id="global-search-trigger"
      aria-label="Search (Cmd+K)"
      className={cn(
        'w-full flex items-center gap-2.5 px-3 h-9 rounded-[--radius-md]',
        'bg-[--bg-overlay] border border-[--border-subtle]',
        'text-sm text-[--text-muted]',
        'hover:border-[--border-default] hover:text-[--text-secondary]',
        'transition-all duration-[--duration-fast] cursor-pointer'
      )}
      // Full search palette is Phase 15 — just render placeholder for now
      onClick={() => {
        /* TODO Phase 15: open search palette */
        console.log('Search — coming in Phase 15')
      }}
    >
      <Search size={14} />
      <span className="flex-1 text-left text-xs">Search…</span>
      <kbd className="text-[10px] bg-[--bg-muted] px-1.5 py-0.5 rounded border border-[--border-subtle]">
        ⌘K
      </kbd>
    </button>
  )
}
