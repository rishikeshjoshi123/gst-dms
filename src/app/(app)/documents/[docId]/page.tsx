import Link from 'next/link'
import { notFound } from 'next/navigation'
import { ArrowLeft, FileText } from 'lucide-react'

import { TimelineDocumentDetail } from '@/components/matters/TimelineDocumentDetail'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { TrashReadOnlyStrip } from '@/components/trash/TrashReadOnlyStrip'
import { PdfViewer } from '@/components/ui/pdf-viewer'
import {
  getCanonicalDocumentVersionSignedUrl,
  getDocumentsByMatter,
} from '@/lib/actions/document'
import { parseCanonicalDocumentUrlState } from '@/lib/canonical-document-route'
import { getNotes } from '@/lib/actions/notes'
import { documentInspectorIds } from '@/lib/documents/document-inspector-ids'
import { getDocumentInspectorMetadata } from '@/lib/documents/inspector-effective-metadata'
import { shapeDocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'
import { getCanonicalAssignedDocument } from '@/lib/trash/exact-resource'

type CanonicalDocumentPageProps = {
  params: Promise<{ docId: string }>
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}

export default async function CanonicalDocumentPage({ params, searchParams }: CanonicalDocumentPageProps) {
  const [{ docId }, query] = await Promise.all([params, searchParams])
  const sourceLocator = parseCanonicalDocumentUrlState(query)
  const expectedMatterId = sourceLocator.matterId
  const exactDocument = await getCanonicalAssignedDocument(docId, expectedMatterId)
  if (!exactDocument) notFound()

  const isTrashReadOnly = exactDocument.state === 'trash'
  const doc = isTrashReadOnly ? exactDocument.data.record : exactDocument.record
  const matterId = doc.matter_id

  const selectedVersionId = sourceLocator.versionId ?? doc.current_version_id
  const signedDocument = selectedVersionId
    ? await getCanonicalDocumentVersionSignedUrl(
      docId,
      selectedVersionId,
      isTrashReadOnly ? exactDocument.expectedMatterId : undefined,
    )
    : null
  const signedDocumentError = signedDocument && 'error' in signedDocument ? signedDocument.error : null
  const signedDocumentUrl = signedDocument && 'url' in signedDocument ? signedDocument.url : null
  const notes = isTrashReadOnly ? exactDocument.data.notes : await getNotes({ documentId: docId })
  const allDocsData = isTrashReadOnly ? null : await getDocumentsByMatter(matterId)
  const allDocuments = isTrashReadOnly
    ? exactDocument.data.documents
    : [...allDocsData!.proceedings, ...allDocsData!.supporting]
  const links = isTrashReadOnly ? exactDocument.data.links : allDocsData!.links
  const inspectorIds = documentInspectorIds(doc.id, allDocuments)
  const inspectorMetadata = isTrashReadOnly
    ? shapeDocumentInspectorMetadata(inspectorIds, exactDocument.data.inspectorMetadataRows)
    : await getDocumentInspectorMetadata(inspectorIds)

  const safeFileLabel = doc.effective_filename || doc.display_title
  const effectiveDocument = inspectorMetadata[doc.id]
  const documentTitle = effectiveDocument?.state === 'available'
    ? effectiveDocument.referenceNumber || doc.display_title || safeFileLabel || 'Document (reference unavailable)'
    : doc.display_title || safeFileLabel || 'Document'

  const breadcrumbs = [
    { label: 'Documents', href: '/documents' },
    { label: doc.matters?.title || 'Matter', href: `/matters/${matterId}` },
    { label: documentTitle },
  ]

  return (
    <div className="flex w-full flex-1 animate-fade-in flex-col gap-4 overflow-hidden">
      <BreadcrumbSetter breadcrumbs={breadcrumbs} />
      {isTrashReadOnly && <TrashReadOnlyStrip context={exactDocument.context} />}

      <div className="flex shrink-0 items-center gap-4">
        <Link
          href={`/matters/${matterId}`}
          className="flex min-h-11 items-center gap-2 text-sm text-[var(--text-muted)] transition-colors hover:text-[var(--text-primary)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
        >
          <ArrowLeft size={16} aria-hidden="true" />
          Back to Matter
        </Link>
      </div>

      <div className="custom-scrollbar flex min-h-0 flex-1 flex-col gap-6 overflow-y-auto overscroll-contain pr-1 lg:flex-row lg:overflow-hidden lg:pr-0">
        <div className="h-[55vh] min-h-72 w-full shrink-0 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] shadow-[var(--shadow-sm)] lg:h-full lg:w-[65%]">
          {signedDocumentError ? (
            <div role="alert" className="flex h-full min-h-72 flex-col items-center justify-center gap-3 p-6 text-center">
              <div className="flex h-11 w-11 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--danger-muted)] text-[var(--danger)]">
                <FileText size={20} aria-hidden="true" />
              </div>
              <div className="max-w-sm space-y-1">
                <h2 className="text-section-heading text-[var(--text-primary)]">PDF unavailable</h2>
                <p className="text-body text-[var(--text-secondary)]">{signedDocumentError}</p>
              </div>
            </div>
          ) : signedDocumentUrl ? (
            <PdfViewer url={signedDocumentUrl} initialPage={sourceLocator.page ?? 1} />
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

        <div className="h-[70vh] min-h-96 w-full shrink-0 lg:h-full lg:w-[35%]">
          <TimelineDocumentDetail
            doc={doc}
            allDocuments={allDocuments}
            links={links}
            notes={notes}
            effectiveMetadata={inspectorMetadata[doc.id]}
            inspectorMetadataByDocumentId={inspectorMetadata}
            readOnly={isTrashReadOnly}
          />
        </div>
      </div>
    </div>
  )
}
