import Link from 'next/link'
import { ArrowRight, Clock3, Trash2 } from 'lucide-react'

import type { TrashRetentionTeamAttentionItem } from '@/lib/trash/retention-policy'

const resourceLabel = { client: 'Client', matter: 'Matter', document: 'Document' } as const

function formatScheduledAt(value: string) {
  return new Intl.DateTimeFormat('en-IN', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'Asia/Kolkata',
  }).format(new Date(value))
}

export function TrashRetentionTeamAttentionPanel({ items }: { items: TrashRetentionTeamAttentionItem[] }) {
  if (items.length === 0) return null
  return (
    <section className="mb-8 overflow-hidden rounded-[var(--radius-md)] border border-[var(--warning)] bg-[var(--surface)]" aria-labelledby="trash-team-attention-title">
      <div className="flex min-h-11 items-center gap-2 border-b border-[var(--border)] bg-[var(--warning-muted)] px-4 py-3">
        <Trash2 className="size-4 shrink-0 text-[var(--warning)]" aria-hidden="true" />
        <h2 id="trash-team-attention-title" className="text-sm font-semibold text-[var(--text-primary)]">Team attention</h2>
        <span className="text-xs text-[var(--text-muted)]">{items.length} Trash {items.length === 1 ? 'group' : 'groups'} nearing permanent deletion</span>
      </div>
      <div className="divide-y divide-[var(--border)]">
        {items.map((item) => (
          <div key={item.operationId} className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
            <div className="min-w-0">
              <p className="break-words text-sm font-semibold text-[var(--text-primary)]">{item.rootLabel}</p>
              <p className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-[var(--text-muted)]">
                <span>{resourceLabel[item.resourceType]} in Trash</span>
                <span aria-hidden="true">·</span>
                <span className="inline-flex items-center gap-1"><Clock3 className="size-3.5" aria-hidden="true" />Scheduled {formatScheduledAt(item.scheduledPermanentDeletionAt)}</span>
              </p>
            </div>
            <Link href={`/trash?selected=${item.operationId}`} className="touch-target inline-flex min-h-11 shrink-0 items-center justify-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 text-xs font-medium text-[var(--text-primary)] transition-colors hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">
              Review Trash group
              <ArrowRight className="size-4" aria-hidden="true" />
            </Link>
          </div>
        ))}
      </div>
    </section>
  )
}
