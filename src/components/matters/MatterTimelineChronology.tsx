import Link from 'next/link'

import { buildMatterReturnPath, canonicalDocumentPath } from '@/lib/canonical-document-route'
import type { MatterTimelineChronologyPage, MatterTimelineRelationshipProjection } from '@/lib/matters/workspace-read'
import { matterTimelineVisibleRange } from '@/lib/matters/workspace-timeline-page'
import { buildMatterDocumentSelectionHref, buildMatterTimelineFiltersHref, buildMatterTimelinePageHref, buildMatterTimelineViewHref, type MatterInspectorView } from '@/lib/matters/workspace-route'
import { MatterTimelineFocusCommit, MatterTimelineRowLink } from './MatterTimelineFocusBridge'
import { MatterTimelineFilters } from './MatterTimelineFilters'
import { MatterTimelineInspector, type MatterTimelineNotePreview } from './MatterTimelineInspector'
import { MatterRelationshipAuthoring } from './MatterRelationshipAuthoring'
import type { RelationshipAuthoringContext } from '@/lib/matters/relationship-authoring'

const unavailable = 'Not available'
function label(item: { title: string | null; referenceNumber: string | null }) { return item.title || item.referenceNumber || 'Untitled proceeding' }
function date(value: string | null) { return value ? new Intl.DateTimeFormat('en-GB', { dateStyle: 'medium' }).format(new Date(`${value}T00:00:00`)) : 'Undated' }
function content(value: string | null) {
  if (value === 'metadata_only') return 'PDF not attached'
  if (value === 'source_attached') return 'PDF attached'
  if (value === 'source_indexed') return 'PDF indexed'
  if (value === 'source_unreadable') return 'Source unreadable'
  return unavailable
}
function attention(value: MatterTimelineChronologyPage['items'][number]['attentionState']) {
  if (value === 'failed') return 'Processing failed'
  if (value === 'review') return 'Needs review'
  if (value === 'processing') return 'Processing'
  return 'No attention'
}

export function MatterTimelineChronology({ matterId, page, selectionUnavailable, queryEntries, filters, inspector, notePreview, relationshipProjection, graphAvailable = true, fallbackMessage, authoringContext }: {
  authoringContext?: RelationshipAuthoringContext | null
  matterId: string
  page: MatterTimelineChronologyPage
  selectionUnavailable: boolean
  queryEntries: Array<[string, string]>
  filters: string[]
  inspector: MatterInspectorView
  notePreview?: readonly MatterTimelineNotePreview[]
  relationshipProjection: MatterTimelineRelationshipProjection
  graphAvailable?: boolean
  fallbackMessage?: string
}) {
  const range = matterTimelineVisibleRange(page)
  const returnTo = buildMatterReturnPath(matterId, queryEntries)
  const selected = page.selected
  const rangeLabel = page.total === 0 ? '0 proceedings' : `Showing ${range.start}–${range.end} of ${page.total} proceedings${page.total !== page.unfilteredTotal ? ` · ${page.unfilteredTotal} in matter` : ''}`
  const previous = Math.max(0, page.offset - page.limit)
  const next = page.offset + page.items.length
  const selectionHref = (documentId: string) => buildMatterDocumentSelectionHref(matterId, queryEntries, documentId)
  const identity = (item: MatterTimelineChronologyPage['items'][number]) => <><span className="block truncate font-medium text-[var(--text-primary)]">{label(item)}</span><span className="block truncate text-xs text-[var(--text-muted)]">{item.referenceNumber || item.documentType || unavailable}</span></>

  return (
    <div id={`matter-timeline-chronology-${matterId}`} tabIndex={-1} className="flex h-full min-h-0 flex-col gap-3 pt-2 focus:outline-none lg:pt-3">
      <MatterTimelineFocusCommit selectedDocumentId={selected?.id ?? null} matterId={matterId} snapshot={`${page.sourceRevision ?? 'none'}:${page.offset}`} />
      <div className="flex min-h-11 shrink-0 flex-wrap items-center justify-between gap-2 border-b border-[var(--border)] bg-[var(--surface)] px-3 py-2">
        <div><h2 className="text-sm font-semibold text-[var(--text-primary)]">Chronology</h2><p className="text-xs text-[var(--text-muted)]">{rangeLabel}</p></div>
        <div className="flex flex-wrap items-center gap-2"><MatterTimelineFilters matterId={matterId} entries={queryEntries} filters={filters} />{graphAvailable ? <Link data-timeline-graph-action scroll={false} prefetch={false} href={buildMatterTimelineViewHref(matterId, queryEntries, 'graph')} className="hidden min-h-11 items-center rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 text-sm font-medium text-[var(--text-primary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] lg:inline-flex">Graph</Link> : null}{authoringContext && <MatterRelationshipAuthoring matterId={matterId} context={authoringContext} />}</div>
      </div>

      {fallbackMessage ? <p role="status" className="border border-[var(--border)] bg-[var(--surface)] p-3 text-sm text-[var(--text-secondary)]">{fallbackMessage}</p> : null}
      {selectionUnavailable && <p role="status" className="border border-[var(--border)] bg-[var(--surface)] p-3 text-sm text-[var(--text-secondary)]">The selected proceeding is unavailable.</p>}
      {page.outcome === 'unavailable' ? (
        <p role="status" className="border border-[var(--border)] bg-[var(--surface)] p-4 text-sm text-[var(--text-secondary)]">Timeline is unavailable for this matter.</p>
      ) : page.total === 0 ? (
        <div className="flex min-h-64 flex-1 items-center justify-center border border-dashed border-[var(--border-strong)] bg-[var(--surface)] p-6 text-center">
          <div>
            <h3 className="font-semibold text-[var(--text-primary)]">{filters.length ? 'No proceedings match these filters' : 'No proceeding documents yet'}</h3>
            <p className="mt-1 text-sm text-[var(--text-secondary)]">{filters.length ? 'Adjust or clear the filters to see other proceedings.' : 'Supporting files are available in Files.'}</p>
            {filters.length > 0 && <Link scroll={false} href={buildMatterTimelineFiltersHref(matterId, queryEntries, [])} className="mt-4 inline-flex min-h-11 items-center rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 text-sm font-medium text-[var(--text-primary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">Clear filters</Link>}
          </div>
        </div>
      ) : (
        <div className="min-h-0 flex-1 gap-3 lg:flex">
          <div className="custom-scrollbar hidden min-h-0 flex-1 overflow-auto border border-[var(--border)] lg:block">
            <table className="w-full min-w-[900px] border-collapse text-left text-sm">
              <thead className="sticky top-0 z-10 bg-[var(--surface)] text-xs text-[var(--text-muted)]"><tr>{['Date', 'Document', 'Direction', 'Procedural effect', 'Key fact', 'Attention'].map((heading) => <th key={heading} scope="col" className="border-b border-[var(--border)] px-3 py-3 font-medium">{heading}</th>)}</tr></thead>
              <tbody>{page.items.map((item) => <tr key={item.id} className="h-14 border-b border-[var(--border)] last:border-0 hover:bg-[var(--surface-hover)]"><td className="px-3 text-[var(--text-secondary)]">{date(item.effectiveDate)}</td><td className="max-w-72 px-3"><MatterTimelineRowLink documentId={item.id} href={selectionHref(item.id)} className="block min-w-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">{identity(item)}</MatterTimelineRowLink></td><td className="px-3 capitalize text-[var(--text-secondary)]">{item.direction || unavailable}</td><td className="px-3 text-[var(--text-secondary)]">{unavailable}</td><td className="px-3 text-[var(--text-secondary)]">{unavailable}</td><td className="px-3 text-[var(--text-secondary)]"><span className="inline-flex min-h-7 items-center whitespace-nowrap"><span data-content-state={item.contentAvailability ?? 'unavailable'}>{content(item.contentAvailability)}</span><span className="px-1 text-[var(--text-muted)]" aria-hidden="true">·</span><span data-attention-state={item.attentionState}>{attention(item.attentionState)}</span></span></td></tr>)}</tbody>
            </table>
          </div>
          <ul className="custom-scrollbar min-h-0 flex-1 divide-y divide-[var(--border)] overflow-y-auto border border-[var(--border)] bg-[var(--surface)] lg:hidden" aria-label="Proceeding chronology">{page.items.map((item) => <li key={item.id} className="p-3"><div className="flex items-start justify-between gap-3"><Link scroll={false} href={canonicalDocumentPath(item.id, { matterId, returnTo })} className="block min-h-11 min-w-0 flex-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">{identity(item)}</Link><span className="shrink-0 text-xs text-[var(--text-muted)]">{date(item.effectiveDate)}</span></div><p className="mt-1 truncate text-xs text-[var(--text-secondary)]"><span className="capitalize">{item.direction || unavailable}</span> · {content(item.contentAvailability)} · {attention(item.attentionState)}</p><p className="truncate text-xs text-[var(--text-muted)]">Effect: {unavailable} · Key fact: {unavailable}</p></li>)}</ul>

          {selected ? <MatterTimelineInspector matterId={matterId} selected={selected} queryEntries={queryEntries} inspector={inspector} notePreview={notePreview} relationshipProjection={relationshipProjection} authoringContext={authoringContext} /> : null}
        </div>
      )}

      {page.total > 0 && <nav aria-label="Chronology pages" className="flex min-h-11 shrink-0 items-center justify-between gap-2 border-t border-[var(--border)] bg-[var(--surface)] px-3 py-2"><p className="text-sm text-[var(--text-secondary)]">{rangeLabel}</p><div className="flex gap-2">{page.offset > 0 ? <Link scroll={false} className="inline-flex min-h-11 items-center px-3 text-sm font-medium text-[var(--text-primary)]" href={buildMatterTimelinePageHref(matterId, queryEntries, { offset: previous, limit: page.limit })}>Previous</Link> : <span className="inline-flex min-h-11 items-center px-3 text-sm text-[var(--text-disabled)]">Previous</span>}{page.offset + page.items.length < page.total ? <Link scroll={false} className="inline-flex min-h-11 items-center px-3 text-sm font-medium text-[var(--text-primary)]" href={buildMatterTimelinePageHref(matterId, queryEntries, { offset: next, limit: page.limit })}>Next</Link> : <span className="inline-flex min-h-11 items-center px-3 text-sm text-[var(--text-disabled)]">Next</span>}</div></nav>}
    </div>
  )
}
