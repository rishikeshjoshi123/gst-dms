import type { ReactNode } from 'react'
import Link from 'next/link'
import { AlertTriangle, ArrowUpRight } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import {
  MATTER_CURRENT_FORUM_LABELS,
  MATTER_WORK_STATE_LABELS,
  type MatterCurrentForum,
  type MatterWorkState,
} from '@/lib/matters/matter-state'
import type { MatterSectionId } from '@/lib/matters/workspace-route'
import { MatterSectionNavigation } from './MatterSectionNavigation'

type MatterShellRecord = {
  id: string
  title: string
  matter_code: string | null
  financial_year: string | null
  status: string
  work_state: MatterWorkState
  current_forum: MatterCurrentForum
  clients?: { name?: string | null } | null
}

export function MatterWorkspaceShell({
  matter,
  section,
  queryEntries,
  readOnly,
  children,
}: {
  matter: MatterShellRecord
  section: MatterSectionId
  queryEntries: Array<[string, string]>
  readOnly: boolean
  children: ReactNode
}) {
  const statusLabel = MATTER_WORK_STATE_LABELS[matter.work_state]
  const isClosed = matter.work_state === 'closed'

  return (
    <div className="flex h-full min-h-0 flex-1 flex-col overflow-hidden -mt-2">
      <header className="shrink-0 border-b border-[var(--border)] bg-[var(--bg)] py-3">
        <div className="flex min-w-0 flex-wrap items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            <div className="flex min-w-0 items-center gap-2">
              <h1 className="min-w-0 truncate text-xl font-semibold text-[var(--text-primary)]" title={matter.title}>
                {matter.title}
              </h1>
              <Badge variant={matter.work_state === 'active' ? 'default' : 'muted'} className="shrink-0 min-w-20 justify-center">
                {statusLabel}
              </Badge>
            </div>
            <p className="mt-1 line-clamp-2 text-xs text-[var(--text-secondary)] sm:truncate">
              {[matter.matter_code || 'No matter code', matter.financial_year || 'Financial year not set', MATTER_CURRENT_FORUM_LABELS[matter.current_forum]]
                .filter(Boolean)
                .join(' · ')}
            </p>
          </div>
          {!readOnly && (
            <Link
              href={`/documents?matterId=${encodeURIComponent(matter.id)}`}
              className="inline-flex min-h-11 shrink-0 items-center justify-center gap-2 rounded-[var(--radius-sm)] border border-[var(--primary)] bg-[var(--primary)] px-4 text-sm font-medium text-[var(--on-accent)] shadow-[var(--shadow-sm)] transition-colors hover:bg-[var(--primary-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
            >
              Open Workbench <ArrowUpRight size={16} aria-hidden="true" />
            </Link>
          )}
        </div>
        {!readOnly && isClosed && (
          <div className="mt-3 flex items-start gap-2 border border-[color-mix(in_srgb,var(--danger)_30%,transparent)] bg-[var(--danger-muted)] p-3 text-sm text-[var(--danger)]">
            <AlertTriangle size={17} aria-hidden="true" className="mt-0.5 shrink-0" />
            <p>This matter is {statusLabel}. Uploading new documents is disabled.</p>
          </div>
        )}
      </header>

      <MatterSectionNavigation matterId={matter.id} activeSection={section} entries={queryEntries} />

      <main
        id="matter-section-body"
        className={section === 'timeline'
          ? 'min-h-0 flex-1 overflow-hidden pb-[76px] md:flex md:flex-col md:pb-0'
          : 'custom-scrollbar min-h-0 flex-1 overflow-y-auto overflow-x-hidden pb-[76px] pt-3 md:pb-6'}
      >
        {children}
      </main>
    </div>
  )
}
