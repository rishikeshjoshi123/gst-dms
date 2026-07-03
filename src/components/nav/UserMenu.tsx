'use client'

import { useTransition, useEffect, useState } from 'react'
import { LogOut, Settings, ChevronsUpDown, Moon, Sun } from 'lucide-react'
import { useTheme } from 'next-themes'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Avatar } from '@/components/ui/avatar'
import { signOut } from '@/lib/actions/auth'
import { switchOrganisation } from '@/lib/actions/org'
import Link from 'next/link'

interface Org {
  id: string
  name: string
  role: string
}

interface UserMenuProps {
  user: {
    email: string
    fullName: string
    avatarUrl?: string | null
  }
  currentOrg: Org
  allOrgs: Org[]
}

export function UserMenu({ user, currentOrg, allOrgs }: UserMenuProps) {
  const [isPending, startTransition] = useTransition()
  const { theme, setTheme } = useTheme()
  const [mounted, setMounted] = useState(false)

  useEffect(() => setMounted(true), [])

  function handleSwitch(orgId: string) {
    startTransition(async () => {
      await switchOrganisation(orgId)
    })
  }

  function handleSignOut() {
    startTransition(async () => {
      await signOut()
    })
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          id="user-menu-trigger"
          aria-label="User menu"
          disabled={isPending}
          className="flex items-center justify-center rounded-full outline-none focus-visible:ring-2 focus-visible:ring-[--accent] cursor-pointer"
        >
          <Avatar
            name={user.fullName || user.email}
            src={user.avatarUrl}
            size="sm"
          />
        </button>
      </DropdownMenuTrigger>

      <DropdownMenuContent side="bottom" align="end" className="w-56">
        {/* Current org */}
        <DropdownMenuLabel className="text-[12px] font-medium uppercase tracking-wide text-[var(--text-secondary)]">
          Current Workspace
        </DropdownMenuLabel>
        <DropdownMenuLabel className="text-[14px] font-semibold text-[var(--text-primary)] pt-0 pb-2">
          {currentOrg.name}
        </DropdownMenuLabel>

        {/* Workspaces list */}
        {allOrgs.length > 0 && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuLabel className="text-[12px] font-medium uppercase tracking-wide text-[var(--text-secondary)] pt-2">
              Workspaces
            </DropdownMenuLabel>
            {allOrgs.map(org => (
              <DropdownMenuItem
                key={org.id}
                onClick={() => handleSwitch(org.id)}
                className="cursor-pointer flex items-center gap-2"
              >
                <div className="w-1.5 h-1.5 flex items-center justify-center shrink-0">
                  {org.id === currentOrg.id && (
                    <span className="w-1.5 h-1.5 rounded-full bg-[var(--accent)]" />
                  )}
                </div>
                <span>{org.name}</span>
              </DropdownMenuItem>
            ))}
          </>
        )}

        <DropdownMenuSeparator />

        <DropdownMenuItem asChild>
          <Link href="/settings">
            <Settings size={14} />
            <span>Settings</span>
          </Link>
        </DropdownMenuItem>

        {mounted && (
          <DropdownMenuItem
            onClick={(e) => {
              e.preventDefault()
              setTheme(theme === 'dark' ? 'light' : 'dark')
            }}
            className="cursor-pointer"
          >
            {theme === 'dark' ? <Sun size={14} /> : <Moon size={14} />}
            <span>{theme === 'dark' ? 'Light mode' : 'Dark mode'}</span>
          </DropdownMenuItem>
        )}

        <DropdownMenuSeparator />

        <DropdownMenuItem destructive onClick={handleSignOut}>
          <LogOut size={14} />
          Sign out
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
