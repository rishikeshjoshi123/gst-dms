import Link from 'next/link'
import { ArrowUpRight } from 'lucide-react'

import { buildMatterReturnPath, canonicalDocumentPath } from '@/lib/canonical-document-route'
import type { MatterTimelineChronologyPage, MatterTimelineRelationshipProjection } from '@/lib/matters/workspace-read'
import { describeMatterTimelineRelationship, matterTimelineVisibleRange } from '@/lib/matters/workspace-timeline-page'
import { buildMatterDocumentSelectionHref, buildMatterInspectorHref, buildMatterSectionHref, buildMatterTimelineFiltersHref, buildMatterTimelinePageHref, MATTER_INSPECTOR_LABELS, type MatterInspectorView } from '@/lib/matters/workspace-route'
import { MatterTimelineCloseLink, MatterTimelineFocusCommit, MatterTimelineRowLink } from './MatterTimelineFocusBridge'
import { MatterTimelineFilters } from './MatterTimelineFilters'

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

export type MatterTimelineNotePreview = {
  id: string
  content: string
  created_at: string
  authorLabel: string | null
}

export function MatterTimelineChronology({ matterId, page, selectionUnavailable, queryEntries, filters, inspector, notePreview, relationshipProjection }: {
  matterId: string
  page: MatterTimelineChronologyPage
  selectionUnavailable: boolean
  queryEntries: Array<[string, string]>
  filters: string[]
  inspector: MatterInspectorView
  notePreview?: readonly MatterTimelineNotePreview[]
  relationshipProjection: MatterTimelineRelationshipProjection
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
        <div className="flex items-center gap-2"><p className="hidden text-xs text-[var(--text-secondary)] xl:block">Chronology is shown while the relationship graph is being prepared.</p><MatterTimelineFilters matterId={matterId} entries={queryEntries} filters={filters} /></div>
      </div>

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

          {selected && (
            <aside className="hidden min-h-0 w-[392px] shrink-0 flex-col border-l border-[var(--border)] bg-[var(--surface)] lg:flex" aria-label="Selected proceeding">
              <div className="shrink-0 border-b border-[var(--border)] p-4">
                <div className="flex items-start justify-between gap-3"><div className="min-w-0"><p className="text-xs text-[var(--text-muted)]">Selected proceeding</p><h3 className="mt-1 truncate font-semibold text-[var(--text-primary)]">{label(selected)}</h3></div><MatterTimelineCloseLink documentId={selected.id} href={buildMatterDocumentSelectionHref(matterId, queryEntries, null)} className="inline-flex min-h-11 items-center rounded-[var(--radius-sm)] px-3 text-sm text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">Close</MatterTimelineCloseLink></div>
                <Link scroll={false} href={canonicalDocumentPath(selected.id, { matterId, returnTo })} className="mt-3 inline-flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] bg-[var(--primary)] px-3 text-sm font-medium text-[var(--on-accent)]">Open document <ArrowUpRight size={15} aria-hidden="true" /></Link>
              </div>
              <nav className="flex shrink-0 gap-1 border-b border-[var(--border)] px-3" aria-label="Inspector views">{(['overview', 'relationships', 'notes'] as const).map((view) => <Link scroll={false} key={view} href={buildMatterInspectorHref(matterId, queryEntries, view)} aria-current={inspector === view ? 'page' : undefined} className={inspector === view ? 'inline-flex min-h-11 items-center border-b-2 border-[var(--primary)] px-2 text-sm font-medium text-[var(--primary)]' : 'inline-flex min-h-11 items-center px-2 text-sm text-[var(--text-secondary)] hover:text-[var(--text-primary)]'}>{MATTER_INSPECTOR_LABELS[view]}</Link>)}</nav>
              <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto p-4">
                {inspector === 'overview' && <dl className="space-y-3 text-sm"><div><dt className="text-[var(--text-muted)]">Document type</dt><dd className="text-[var(--text-primary)]">{selected.documentType || unavailable}</dd></div><div><dt className="text-[var(--text-muted)]">Reference</dt><dd className="text-[var(--text-primary)]">{selected.referenceNumber || unavailable}</dd></div><div><dt className="text-[var(--text-muted)]">Effective date</dt><dd className="text-[var(--text-primary)]">{date(selected.effectiveDate)}</dd></div><div><dt className="text-[var(--text-muted)]">Direction</dt><dd className="capitalize text-[var(--text-primary)]">{selected.direction || unavailable}</dd></div><div><dt className="text-[var(--text-muted)]">Content</dt><dd className="text-[var(--text-primary)]">{content(selected.contentAvailability)}</dd></div><div><dt className="text-[var(--text-muted)]">Attention</dt><dd className="text-[var(--text-primary)]">{attention(selected.attentionState)}</dd></div><div><dt className="text-[var(--text-muted)]">Procedural effect</dt><dd className="text-[var(--text-primary)]">{unavailable}</dd></div><div><dt className="text-[var(--text-muted)]">Key fact</dt><dd className="text-[var(--text-primary)]">{unavailable}</dd></div></dl>}
                {inspector === 'relationships' && (
                  <div className="text-sm">
                    <h4 className="font-medium text-[var(--text-primary)]">Effective relationships</h4>
                    {relationshipProjection.outcome === 'unavailable' ? (
                      <p role="status" className="mt-2 text-[var(--text-secondary)]">Relationships are temporarily unavailable.</p>
                    ) : relationshipProjection.relationships.length === 0 ? (
                      <p className="mt-2 text-[var(--text-secondary)]">No active Timeline relationships involve this proceeding.</p>
                    ) : (
                      <ol className="mt-3 space-y-3">
                        {relationshipProjection.relationships.map((relationship) => {
                          const description = describeMatterTimelineRelationship(relationship, selected.id)
                          return (
                            <li key={relationship.id} className="border border-[var(--border)] bg-[var(--surface)] p-3">
                              <p className="text-xs font-medium uppercase tracking-wide text-[var(--text-muted)]">
                                {description.direction === 'outgoing' ? 'Outgoing' : 'Incoming'} · {relationship.verification === 'human' ? 'Human verified' : relationship.verification === 'policy_confirmed' ? 'Policy confirmed' : 'Provisional'}
                              </p>
                              <p className="mt-2 text-[var(--text-primary)]">{description.canonicalSentence}</p>
                              <dl className="mt-2 border-t border-[var(--border)] pt-2">
                                <dt className="text-xs text-[var(--text-muted)]">Timeline progression</dt>
                                <dd className="mt-1 text-[var(--text-secondary)]">{description.progressionSentence}</dd>
                              </dl>
                            </li>
                          )
                        })}
                      </ol>
                    )}
                  </div>
                )}
                {inspector === 'notes' && <div className="text-sm"><h4 className="font-medium text-[var(--text-primary)]">Document notes</h4>{notePreview && notePreview.length > 0 ? <ol className="mt-3 space-y-3">{notePreview.map((note) => <li key={note.id} className="border-b border-[var(--border)] pb-3 last:border-0"><p className="whitespace-pre-wrap break-words text-[var(--text-primary)]">{note.content}</p><p className="mt-1 text-xs text-[var(--text-muted)]">{note.authorLabel || 'Author unavailable'} · {new Intl.DateTimeFormat('en-GB', { dateStyle: 'medium' }).format(new Date(note.created_at))}</p></li>)}</ol> : <p className="mt-2 text-[var(--text-secondary)]">No notes are attached to this proceeding.</p>}<Link scroll={false} href={buildMatterSectionHref(matterId, queryEntries, 'notes')} className="mt-4 inline-flex min-h-11 items-center rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 font-medium text-[var(--text-primary)]">Open Matter Notes</Link></div>}
              </div>
            </aside>
          )}
        </div>
      )}

      {page.total > 0 && <nav aria-label="Chronology pages" className="flex min-h-11 shrink-0 items-center justify-between gap-2 border-t border-[var(--border)] bg-[var(--surface)] px-3 py-2"><p className="text-sm text-[var(--text-secondary)]">{rangeLabel}</p><div className="flex gap-2">{page.offset > 0 ? <Link scroll={false} className="inline-flex min-h-11 items-center px-3 text-sm font-medium text-[var(--text-primary)]" href={buildMatterTimelinePageHref(matterId, queryEntries, { offset: previous, limit: page.limit })}>Previous</Link> : <span className="inline-flex min-h-11 items-center px-3 text-sm text-[var(--text-disabled)]">Previous</span>}{page.offset + page.items.length < page.total ? <Link scroll={false} className="inline-flex min-h-11 items-center px-3 text-sm font-medium text-[var(--text-primary)]" href={buildMatterTimelinePageHref(matterId, queryEntries, { offset: next, limit: page.limit })}>Next</Link> : <span className="inline-flex min-h-11 items-center px-3 text-sm text-[var(--text-disabled)]">Next</span>}</div></nav>}
    </div>
  )
}
