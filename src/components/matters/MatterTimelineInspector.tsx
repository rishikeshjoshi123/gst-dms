import Link from 'next/link'
import { ArrowUpRight } from 'lucide-react'

import { buildMatterReturnPath, canonicalDocumentPath } from '@/lib/canonical-document-route'
import type { MatterTimelineChronologyItem, MatterTimelineRelationshipProjection } from '@/lib/matters/workspace-read'
import {
  buildMatterDocumentSelectionHref,
  buildMatterInspectorHref,
  buildMatterSectionHref,
  MATTER_INSPECTOR_LABELS,
  type MatterInspectorView,
} from '@/lib/matters/workspace-route'
import { MatterTimelineCloseLink } from './MatterTimelineFocusBridge'
import { MatterEffectiveRelationshipList } from './MatterRelationshipAuthoring'
import type { RelationshipAuthoringContext } from '@/lib/matters/relationship-authoring'

const unavailable = 'Not available'
function label(item: Pick<MatterTimelineChronologyItem, 'title' | 'referenceNumber'>) { return item.title || item.referenceNumber || 'Untitled proceeding' }
function date(value: string | null) { return value ? new Intl.DateTimeFormat('en-GB', { dateStyle: 'medium' }).format(new Date(`${value}T00:00:00Z`)) : 'Date unavailable' }
function content(value: string | null) {
  if (value === 'metadata_only') return 'PDF not attached'
  if (value === 'source_attached') return 'PDF attached'
  if (value === 'source_indexed') return 'PDF indexed'
  if (value === 'source_unreadable') return 'Source unreadable'
  return unavailable
}
function attention(value: MatterTimelineChronologyItem['attentionState']) {
  if (value === 'failed') return 'Processing failed'
  if (value === 'review') return 'Needs review'
  if (value === 'processing') return 'Processing'
  return 'No attention'
}

export type MatterTimelineNotePreview = {
  id: string
  content: string
  created_at: string
  authorLabel: string | null
}

export function MatterTimelineInspector({ matterId, selected, queryEntries, inspector, notePreview, relationshipProjection, authoringContext }: {
  authoringContext?: RelationshipAuthoringContext | null
  matterId: string
  selected: MatterTimelineChronologyItem
  queryEntries: Array<[string, string]>
  inspector: MatterInspectorView
  notePreview?: readonly MatterTimelineNotePreview[]
  relationshipProjection: MatterTimelineRelationshipProjection
}) {
  const returnTo = buildMatterReturnPath(matterId, queryEntries)
  return (
    <aside id={`matter-inspector-${matterId}`} tabIndex={-1} className="hidden min-h-0 w-[392px] shrink-0 flex-col border-l border-[var(--border)] bg-[var(--surface)] lg:flex" aria-label="Selected proceeding">
      <div className="shrink-0 border-b border-[var(--border)] p-4">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0"><p className="text-xs text-[var(--text-muted)]">Selected proceeding</p><h3 className="mt-1 truncate font-semibold text-[var(--text-primary)]">{label(selected)}</h3></div>
          <MatterTimelineCloseLink documentId={selected.id} href={buildMatterDocumentSelectionHref(matterId, queryEntries, null)} className="inline-flex min-h-11 items-center rounded-[var(--radius-sm)] px-3 text-sm text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">Close</MatterTimelineCloseLink>
        </div>
        <Link scroll={false} prefetch={false} href={canonicalDocumentPath(selected.id, { matterId, returnTo })} className="mt-3 inline-flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] bg-[var(--primary)] px-3 text-sm font-medium text-[var(--on-accent)]">Open document <ArrowUpRight size={15} aria-hidden="true" /></Link>
      </div>
      <nav className="flex shrink-0 gap-1 border-b border-[var(--border)] px-3" aria-label="Inspector views">
        {(['overview', 'relationships', 'notes'] as const).map((view) => <Link scroll={false} prefetch={false} key={view} href={buildMatterInspectorHref(matterId, queryEntries, view)} aria-current={inspector === view ? 'page' : undefined} className={inspector === view ? 'inline-flex min-h-11 items-center border-b-2 border-[var(--primary)] px-2 text-sm font-medium text-[var(--primary)]' : 'inline-flex min-h-11 items-center px-2 text-sm text-[var(--text-secondary)] hover:text-[var(--text-primary)]'}>{MATTER_INSPECTOR_LABELS[view]}</Link>)}
      </nav>
      <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto p-4">
        {inspector === 'overview' && <dl className="space-y-3 text-sm"><div><dt className="text-[var(--text-muted)]">Document type</dt><dd className="text-[var(--text-primary)]">{selected.documentType || unavailable}</dd></div><div><dt className="text-[var(--text-muted)]">Reference</dt><dd className="text-[var(--text-primary)]">{selected.referenceNumber || unavailable}</dd></div><div><dt className="text-[var(--text-muted)]">Effective date</dt><dd className="text-[var(--text-primary)]">{date(selected.effectiveDate)}</dd></div><div><dt className="text-[var(--text-muted)]">Direction</dt><dd className="capitalize text-[var(--text-primary)]">{selected.direction || unavailable}</dd></div><div><dt className="text-[var(--text-muted)]">Content</dt><dd className="text-[var(--text-primary)]">{content(selected.contentAvailability)}</dd></div><div><dt className="text-[var(--text-muted)]">Attention</dt><dd className="text-[var(--text-primary)]">{attention(selected.attentionState)}</dd></div><div><dt className="text-[var(--text-muted)]">Procedural effect</dt><dd className="text-[var(--text-primary)]">{unavailable}</dd></div><div><dt className="text-[var(--text-muted)]">Key fact</dt><dd className="text-[var(--text-primary)]">{unavailable}</dd></div></dl>}
        {inspector === 'relationships' && (
          <div className="text-sm">
            <h4 className="font-medium text-[var(--text-primary)]">Effective relationships</h4>
            <MatterEffectiveRelationshipList key={`${matterId}:${selected.id}`} matterId={matterId} selectedDocumentId={selected.id} projection={relationshipProjection} context={authoringContext} />
          </div>
        )}
        {inspector === 'notes' && <div className="text-sm"><h4 className="font-medium text-[var(--text-primary)]">Document notes</h4>{notePreview && notePreview.length > 0 ? <ol className="mt-3 space-y-3">{notePreview.map((note) => <li key={note.id} className="border-b border-[var(--border)] pb-3 last:border-0"><p className="whitespace-pre-wrap break-words text-[var(--text-primary)]">{note.content}</p><p className="mt-1 text-xs text-[var(--text-muted)]">{note.authorLabel || 'Author unavailable'} · {new Intl.DateTimeFormat('en-GB', { dateStyle: 'medium' }).format(new Date(note.created_at))}</p></li>)}</ol> : <p className="mt-2 text-[var(--text-secondary)]">No notes are attached to this proceeding.</p>}<Link scroll={false} prefetch={false} href={buildMatterSectionHref(matterId, queryEntries, 'notes')} className="mt-4 inline-flex min-h-11 items-center rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 font-medium text-[var(--text-primary)]">Open Matter Notes</Link></div>}
      </div>
    </aside>
  )
}
