import Link from 'next/link'
import { ArrowUpRight, FileText } from 'lucide-react'

import { canonicalDocumentPath } from '@/lib/canonical-document-route'
import type { DocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'
import { buildMatterDocumentSelectionHref } from '@/lib/matters/workspace-route'
import { buildMatterInspectorHref, MATTER_INSPECTOR_LABELS, type MatterInspectorView } from '@/lib/matters/workspace-route'

type SupportingFile = {
  id: string
  matter_id: string
  display_title: string | null
  effective_filename: string | null
  document_category: string | null
  reference_number: string | null
  content_availability?: string | null
}

export function MatterFilesSection({
  matterId,
  documents,
  selectedDocumentId,
  selectionUnavailable,
  inspectorMetadata,
  inspector,
  queryEntries,
}: {
  matterId: string
  documents: SupportingFile[]
  selectedDocumentId: string | null
  selectionUnavailable: boolean
  inspectorMetadata?: DocumentInspectorMetadata
  inspector: MatterInspectorView
  queryEntries: Array<[string, string]>
}) {
  const selected = documents.find((document) => document.id === selectedDocumentId) ?? null

  return (
    <div className="flex min-h-full flex-col gap-3">
      <div className="flex min-h-11 flex-wrap items-center justify-between gap-2 border-b border-[var(--border)] bg-[var(--surface)] px-3 py-2">
        <div className="min-w-0">
          <h2 className="text-sm font-semibold text-[var(--text-primary)]">Supporting files</h2>
          <p className="text-xs text-[var(--text-muted)]">Evidence and supporting material for this matter.</p>
        </div>
        <Link
          href={`/documents?matterId=${encodeURIComponent(matterId)}`}
          className="inline-flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 text-sm font-medium text-[var(--text-primary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
        >
          Open Workbench <ArrowUpRight size={15} aria-hidden="true" />
        </Link>
      </div>

      {selectionUnavailable && (
        <div role="status" className="border border-[var(--border)] bg-[var(--surface)] p-4 text-sm text-[var(--text-secondary)]">
          The selected document is unavailable. Choose a file from this matter.
        </div>
      )}

      {selected && (
        <aside className="border border-[var(--border-strong)] bg-[var(--surface)] p-4" aria-label="Selected file overview">
          <nav aria-label="Selected file sections" className="mb-3 flex flex-wrap gap-1 border-b border-[var(--border)] pb-2">
            {(['overview', 'relationships', 'notes'] as const).map((item) => (
              <Link
                key={item}
                href={buildMatterInspectorHref(matterId, queryEntries, item)}
                aria-current={inspector === item ? 'page' : undefined}
                className={inspector === item
                  ? 'inline-flex min-h-11 items-center rounded-[var(--radius-sm)] bg-[var(--primary-muted)] px-3 text-sm font-medium text-[var(--primary)]'
                  : 'inline-flex min-h-11 items-center rounded-[var(--radius-sm)] px-3 text-sm font-medium text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]'}
              >
                {MATTER_INSPECTOR_LABELS[item]}
              </Link>
            ))}
          </nav>
          <div className="flex min-w-0 flex-wrap items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="text-xs font-medium uppercase tracking-wide text-[var(--text-muted)]">Selected supporting file</p>
              <h3 className="mt-1 truncate font-semibold text-[var(--text-primary)]" title={selected.display_title || selected.effective_filename || undefined}>
                {selected.display_title || selected.effective_filename || 'Untitled document'}
              </h3>
              <p className="mt-1 text-sm text-[var(--text-secondary)]">
                {inspector === 'relationships'
                  ? 'Inspect this document’s procedural relationships from the Timeline.'
                  : inspector === 'notes'
                    ? 'Open Notes to review discussion and source-linked notes for this document.'
                    : inspectorMetadata?.state === 'available'
                  ? [inspectorMetadata.docType, inspectorMetadata.referenceNumber, inspectorMetadata.documentDate].filter(Boolean).join(' · ') || 'Overview available in Workbench.'
                  : 'Detailed source information is available in Workbench.'}
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Link
                href={buildMatterDocumentSelectionHref(matterId, queryEntries, null)}
                className="inline-flex min-h-11 items-center rounded-[var(--radius-sm)] px-3 text-sm font-medium text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
              >
                Close overview
              </Link>
              <Link
                href={canonicalDocumentPath(selected.id, { matterId })}
                className="inline-flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] bg-[var(--primary)] px-3 text-sm font-medium text-[var(--on-accent)] hover:bg-[var(--primary-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
              >
                Open selected file <ArrowUpRight size={15} aria-hidden="true" />
              </Link>
            </div>
          </div>
        </aside>
      )}

      {documents.length === 0 ? (
        <div className="flex min-h-64 flex-col items-center justify-center gap-2 border border-dashed border-[var(--border-strong)] bg-[var(--surface)] p-6 text-center">
          <FileText size={24} aria-hidden="true" className="text-[var(--text-muted)]" />
          <h3 className="font-semibold text-[var(--text-primary)]">No supporting files</h3>
          <p className="text-sm text-[var(--text-secondary)]">Supporting documents added to this matter will appear here.</p>
        </div>
      ) : (
        <ul className="grid grid-cols-1 gap-3 lg:grid-cols-2" aria-label="Supporting files">
          {documents.map((document) => {
            const fileName = document.display_title || document.effective_filename || 'Untitled document'
            const isSelected = document.id === selectedDocumentId
            return (
              <li key={document.id} className="min-w-0 border border-[var(--border)] bg-[var(--surface)] p-4">
                <div className="flex min-w-0 items-start gap-3">
                  <FileText size={18} aria-hidden="true" className="mt-0.5 shrink-0 text-[var(--text-muted)]" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-[var(--text-primary)]" title={fileName}>{fileName}</p>
                    <p className="mt-1 truncate text-xs text-[var(--text-muted)]">
                      {document.document_category?.replaceAll('_', ' ') || document.reference_number || 'Supporting document'}
                    </p>
                  </div>
                </div>
                <div className="mt-3 flex flex-wrap items-center justify-end gap-2">
                  <Link
                    href={buildMatterDocumentSelectionHref(matterId, queryEntries, document.id)}
                    aria-current={isSelected ? 'true' : undefined}
                    className="inline-flex min-h-11 items-center rounded-[var(--radius-sm)] px-3 text-sm font-medium text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
                  >
                    Inspect file
                  </Link>
                  <Link
                    href={canonicalDocumentPath(document.id, { matterId })}
                    className="inline-flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 text-sm font-medium text-[var(--text-primary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
                  >
                    Open in Workbench <ArrowUpRight size={14} aria-hidden="true" />
                  </Link>
                </div>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
