'use client'

import { FileText } from 'lucide-react'
import { useState } from 'react'

import { TimelineDocumentDetail } from '@/components/matters/TimelineDocumentDetail'
import { PdfViewer, type PdfQuotationSelection } from '@/components/ui/pdf-viewer'
import type { PdfSourceFailure } from '@/components/ui/pdf-viewer-model'
import type { DocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'
import { renewCanonicalDocumentVersionSource } from '@/lib/actions/document'
import type { MatterInspectorView } from '@/lib/matters/workspace-route'

type SourceProjection = {
  versionId: string
  versionNumber: number
  pageCount: number
  isCurrent: boolean
  page: number
}

type DocumentWorkbenchDocument = {
  id: string
  matter_id: string
}

type QuotationDraft = {
  sourceIdentity: string
  selection: PdfQuotationSelection
}

export function CanonicalDocumentWorkbench({
  doc,
  allDocuments,
  links,
  notes,
  effectiveMetadata,
  inspectorMetadataByDocumentId,
  source,
  sourceUrl,
  sourceFailure,
  expectedMatterId,
  readOnly,
  canRepairBoundary,
}: {
  doc: DocumentWorkbenchDocument
  allDocuments: unknown[]
  links: unknown[]
  notes: unknown[]
  effectiveMetadata: DocumentInspectorMetadata | undefined
  inspectorMetadataByDocumentId: Record<string, DocumentInspectorMetadata>
  source: SourceProjection | null
  sourceUrl: string | null
  sourceFailure?: PdfSourceFailure
  expectedMatterId?: string
  readOnly: boolean
  canRepairBoundary: boolean
}) {
  const [quotationDraft, setQuotationDraft] = useState<QuotationDraft | null>(null)
  const [inspectorTab, setInspectorTab] = useState<MatterInspectorView>('overview')
  const sourceIdentity = source ? `${doc.id}:${source.versionId}` : null
  const activeQuotationDraft = quotationDraft?.sourceIdentity === sourceIdentity
    ? quotationDraft.selection
    : null

  const createQuotation = (selection: PdfQuotationSelection) => {
    if (!sourceIdentity) return
    setQuotationDraft({ sourceIdentity, selection })
    setInspectorTab('notes')
  }

  const renewSource = source ? async () => renewCanonicalDocumentVersionSource({
    documentId: doc.id,
    documentVersionId: source.versionId,
    expectedMatterId,
    page: source.page,
  }) : undefined

  return (
    <div className="custom-scrollbar flex min-h-0 flex-1 flex-col gap-6 overflow-y-auto overscroll-contain pr-1 lg:flex-row lg:overflow-hidden lg:pr-0">
      <section className="flex h-[55vh] min-h-72 w-full shrink-0 flex-col overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] shadow-[var(--shadow-sm)] lg:h-full lg:w-[65%]">
        {source && (
          <header className="shrink-0 border-b border-[var(--border)] bg-[var(--surface)] px-4 py-3">
            <p className="text-sm font-semibold text-[var(--text-primary)]">
              PDF source · Version {source.versionNumber} · Page {source.page} of {source.pageCount}
            </p>
            <p className="text-xs text-[var(--text-secondary)]">
              {source.isCurrent
                ? 'Current immutable document version'
                : 'Historical immutable document version — current document changes do not alter these bytes'}
            </p>
          </header>
        )}
        <div className="min-h-0 flex-1 overflow-hidden">
          {sourceUrl || sourceFailure ? (
            <PdfViewer
              url={sourceUrl}
              initialPage={source?.page ?? 1}
              initialFailure={sourceFailure}
              onRequestSourceRefresh={renewSource}
              quoteSource={!readOnly && source ? { documentId: doc.id, documentVersionId: source.versionId } : undefined}
              onCreateQuotation={!readOnly && source ? createQuotation : undefined}
            />
          ) : (
            <div className="flex h-full min-h-72 flex-col items-center justify-center gap-3 p-6 text-center">
              <div className="flex h-11 w-11 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--surface-hover)] text-[var(--text-muted)]">
                <FileText size={20} aria-hidden="true" />
              </div>
              <div className="max-w-sm space-y-1">
                <h2 className="text-section-heading text-[var(--text-primary)]">No file attached</h2>
                <p className="text-body text-[var(--text-secondary)]">
                  This document record has no file version yet. A file can be attached later without changing its details.
                </p>
              </div>
            </div>
          )}
        </div>
      </section>

      <section className="flex h-[70vh] min-h-96 w-full shrink-0 flex-col lg:h-full lg:w-[35%]">
        {source && !source.isCurrent && (
          <div className="shrink-0 border border-b-0 border-[var(--border)] bg-[var(--warning-muted)] px-3 py-2 text-xs text-[var(--text-secondary)]">
            Current document metadata · Actions that change the current document are unavailable while historical bytes are displayed.
          </div>
        )}
        <div className="min-h-0 flex-1">
          <TimelineDocumentDetail
            doc={doc}
            allDocuments={allDocuments}
            links={links}
            notes={notes}
            effectiveMetadata={effectiveMetadata}
            inspectorMetadataByDocumentId={inspectorMetadataByDocumentId}
            readOnly={readOnly}
            canRepairBoundary={canRepairBoundary}
            quotationDraft={activeQuotationDraft}
            onQuotationDraftConsumed={() => setQuotationDraft(null)}
            activeTab={inspectorTab}
            onActiveTabChange={setInspectorTab}
            displayedSource={source ? { versionId: source.versionId, page: source.page, historical: !source.isCurrent } : undefined}
          />
        </div>
      </section>
    </div>
  )
}
