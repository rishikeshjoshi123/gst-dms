'use client'

import { useTransition } from 'react'
import { LogOut, Settings, ChevronsUpDown } from 'lucide-react'
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
          className="w-full flex items-center gap-2.5 px-2 py-2 rounded-[--radius-md] hover:bg-[--bg-overlay] transition-colors group cursor-pointer"
        >
          <Avatar
            name={user.fullName || user.email}
            src={user.avatarUrl}
            size="sm"
          />
          <div className="flex-1 min-w-0 text-left">
            <p className="text-xs font-semibold text-[--text-primary] truncate">
              {user.fullName || 'User'}
            </p>
            <p className="text-[10px] text-[--text-muted] truncate">{user.email}</p>
          </div>
          <ChevronsUpDown size={14} className="text-[--text-muted] group-hover:text-[--text-secondary] transition-colors shrink-0" />
        </button>
      </DropdownMenuTrigger>

      <DropdownMenuContent side="top" align="start" className="w-56">
        {/* Current org */}
        <DropdownMenuLabel>{currentOrg.name}</DropdownMenuLabel>

        {/* Other orgs */}
        {allOrgs.filter(o => o.id !== currentOrg.id).length > 0 && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuLabel>Switch workspace</DropdownMenuLabel>
            {allOrgs
              .filter(o => o.id !== currentOrg.id)
              .map(org => (
                <DropdownMenuItem
                  key={org.id}
                  onClick={() => handleSwitch(org.id)}
                >
                  {org.name}
                </DropdownMenuItem>
              ))}
          </>
        )}

        <DropdownMenuSeparator />

        <DropdownMenuItem asChild>
          <Link href="/settings">
            <Settings size={14} />
            Settings
          </Link>
        </DropdownMenuItem>

        <DropdownMenuItem destructive onClick={handleSignOut}>
          <LogOut size={14} />
          Sign out
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
