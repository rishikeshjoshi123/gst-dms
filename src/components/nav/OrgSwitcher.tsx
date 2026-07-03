'use client'

import { useTransition } from 'react'
import { ChevronsUpDown, Building2 } from 'lucide-react'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { switchOrganisation } from '@/lib/actions/org'

interface Org {
  id: string
  name: string
  role: string
}

export function OrgSwitcher({ currentOrg, allOrgs }: { currentOrg: Org; allOrgs: Org[] }) {
  const [isPending, startTransition] = useTransition()

  function handleSwitch(orgId: string) {
    startTransition(async () => {
      await switchOrganisation(orgId)
    })
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          disabled={isPending}
          className="flex w-full items-center gap-3 px-4 h-16 border-b border-white/10 hover:bg-white/5 transition-colors text-left"
        >
          <div className="flex h-8 w-8 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-accent)]">
            <Building2 size={16} className="text-white" />
          </div>
          <div className="flex flex-col min-w-0 flex-1 whitespace-nowrap overflow-hidden opacity-0 group-hover:opacity-100 transition-opacity duration-300">
            <span className="text-[14px] font-bold text-white truncate">{currentOrg.name}</span>
            <span className="text-[12px] text-[var(--text-muted)] truncate">Workspace</span>
          </div>
          <ChevronsUpDown size={14} className="text-[var(--text-muted)] shrink-0 opacity-0 group-hover:opacity-100 transition-opacity duration-300" />
        </button>
      </DropdownMenuTrigger>

      <DropdownMenuContent side="bottom" align="start" className="w-64">
        <DropdownMenuLabel>Workspaces</DropdownMenuLabel>
        {allOrgs.map(org => (
          <DropdownMenuItem
            key={org.id}
            onClick={() => handleSwitch(org.id)}
            className="flex items-center gap-2"
          >
            {org.id === currentOrg.id && <span className="w-1.5 h-1.5 rounded-full bg-[var(--accent)]" />}
            <span className={org.id !== currentOrg.id ? 'ml-3.5' : ''}>{org.name}</span>
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
