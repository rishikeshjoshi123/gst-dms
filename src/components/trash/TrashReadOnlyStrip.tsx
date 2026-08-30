import Link from 'next/link'
import { ArrowLeft, Trash2 } from 'lucide-react'

import type { ExactResourceTrashContext } from '@/lib/trash/exact-resource'
import { RestoreTrashOperationControl } from './RestoreTrashOperationControl'

const resourceLabel = { client: 'Client', matter: 'Matter', document: 'Document' } as const

function formatTrashDate(value: string) {
  try {
    return new Intl.DateTimeFormat('en-IN', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  } catch {
    return value
  }
}

function retentionGuidance(context: ExactResourceTrashContext) {
  if (context.operationState === 'purge_scheduled') {
    return context.retention.purgeScheduledAt
      ? `Permanent deletion was scheduled on ${formatTrashDate(context.retention.purgeScheduledAt)}. The item remains readable until deletion begins.`
      : 'Permanent deletion is scheduled. The item remains readable until deletion begins.'
  }
  if (context.retention.blockerCount > 0) {
    return `${context.retention.blockerCount} ${context.retention.blockerCount === 1 ? 'retention blocker protects' : 'retention blockers protect'} this Trash group.`
  }
  if (context.retention.autoPurgeEnabled && context.retention.autoPurgeAt) {
    return `Organisation policy schedules automatic permanent deletion after ${formatTrashDate(context.retention.autoPurgeAt)}.`
  }
  if (context.retention.mode === 'manual_only') {
    return 'Retention is manual. This Trash group stays available until an authorised permanent-deletion workflow is used.'
  }
  if (context.retention.purgeEligibleAt) {
    return `Retention guidance: eligible for review after ${formatTrashDate(context.retention.purgeEligibleAt)}. Nothing is deleted automatically unless organisation policy enables it.`
  }
  return context.retention.days
    ? `Retention guidance: ${context.retention.days} days from deletion. Nothing is deleted automatically unless organisation policy enables it.`
    : 'Retention guidance is recorded for this Trash group.'
}

export function TrashReadOnlyStrip({ context }: { context: ExactResourceTrashContext }) {
  const inherited = context.cause === 'inherited'
  const rootType = resourceLabel[context.rootResourceType]
  const lineage = inherited
    ? `This item was moved with ${rootType.toLowerCase()} “${context.rootResourceName}”. The ancestor Trash group must be restored; this item has no independent restore action.`
    : `This ${resourceLabel[context.rootResourceType].toLowerCase()} is the root of the Trash group “${context.rootResourceName}”. Restoring returns the whole group; permanent deletion is not available.`

  return (
    <section
      aria-labelledby="trash-read-only-title"
      className="shrink-0 border-y border-[color-mix(in_srgb,var(--danger)_30%,transparent)] bg-[var(--danger-muted)] px-3 py-3 text-[var(--text-primary)] sm:px-4"
    >
      <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-start">
        <div className="flex min-w-0 flex-1 items-start gap-3">
          <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] border border-[color-mix(in_srgb,var(--danger)_30%,transparent)] bg-[var(--surface)] text-[var(--danger)]">
            <Trash2 className="size-4" aria-hidden="true" />
          </span>
          <div className="min-w-0">
            <h2 id="trash-read-only-title" className="text-sm font-semibold text-[var(--danger)]">In Trash — read only</h2>
            <p className="mt-1 break-words text-xs leading-5 text-[var(--text-secondary)]">{lineage}</p>
            <p className="mt-1 break-words text-xs leading-5 text-[var(--text-muted)]">{retentionGuidance(context)}</p>
            <p className="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-xs text-[var(--text-muted)]">
              <span>Deleted by <strong className="font-medium text-[var(--text-secondary)]">{context.trashedByName}</strong></span>
              <span className="font-mono">{formatTrashDate(context.trashedAt)}</span>
              <span>Root operation: <strong className="font-medium text-[var(--text-secondary)]">{rootType} · {context.rootResourceName}</strong></span>
            </p>
          </div>
        </div>
        <div className="flex shrink-0 flex-wrap items-center gap-2 sm:justify-end">
          <Link
            href={`/trash?selected=${encodeURIComponent(context.operationId)}`}
            className="inline-flex min-h-11 shrink-0 items-center justify-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-4 text-sm font-medium text-[var(--text-primary)] transition-colors hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
          >
            <ArrowLeft className="size-4" aria-hidden="true" />
            Back to Trash
          </Link>
          {!inherited && context.restorePreflight && (
            <RestoreTrashOperationControl
              operationId={context.operationId}
              operationName={context.rootResourceName}
              impact="The selected root and every item moved with this operation"
              preflight={context.restorePreflight}
              successPath={context.rootResourceType === 'client'
                ? `/clients/${context.rootResourceId}`
                : context.rootResourceType === 'matter'
                  ? `/matters/${context.rootResourceId}`
                  : ''}
              compact
            />
          )}
        </div>
      </div>
    </section>
  )
}
