import { getDocumentVersionSignedUrl, getDocumentsByMatter, getTrashedDocumentVersionSignedUrl } from '@/lib/actions/document'
import { getNotes } from '@/lib/actions/notes'
import { getDocumentInspectorMetadata } from '@/lib/documents/inspector-effective-metadata'
import { documentInspectorIds } from '@/lib/documents/document-inspector-ids'
import { shapeDocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'
import { notFound } from 'next/navigation'
import { PdfViewer } from '@/components/ui/pdf-viewer'
import { TimelineDocumentDetail } from '@/components/matters/TimelineDocumentDetail'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import Link from 'next/link'
import { ArrowLeft, FileText } from 'lucide-react'
import { getExactDocument } from '@/lib/trash/exact-resource'
import { TrashReadOnlyStrip } from '@/components/trash/TrashReadOnlyStrip'

export default async function DocumentPage(props: { params: Promise<{ id: string; docId: string }> }) {
  const params = await props.params;
  const exactDocument = await getExactDocument(params.id, params.docId)
  if (!exactDocument) notFound()
  const isTrashReadOnly = exactDocument.state === 'trash'
  const doc = isTrashReadOnly ? exactDocument.data.record : exactDocument.record

  const signedDocument = doc.current_version_id
    ? isTrashReadOnly
      ? await getTrashedDocumentVersionSignedUrl(params.id, params.docId, doc.current_version_id)
      : await getDocumentVersionSignedUrl(doc.current_version_id)
    : null
  const notes = isTrashReadOnly ? exactDocument.data.notes : await getNotes({ documentId: params.docId })
  const allDocsData = isTrashReadOnly ? null : await getDocumentsByMatter(params.id)
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
    { label: 'Clients', href: '/clients' },
    { label: doc.matters?.title || 'Matter', href: `/matters/${params.id}` },
    { label: documentTitle }
  ]

  return (
    <div className="flex flex-col flex-1 overflow-hidden gap-4 w-full animate-fade-in">
      <BreadcrumbSetter breadcrumbs={breadcrumbs} />
      {isTrashReadOnly && <TrashReadOnlyStrip context={exactDocument.context} />}

      <div className="flex shrink-0 items-center gap-4">
        <Link href={`/matters/${params.id}`} className="flex min-h-11 items-center gap-2 text-sm text-[var(--text-muted)] transition-colors hover:text-[var(--text-primary)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">
          <ArrowLeft size={16} />
          Back to Matter
        </Link>
      </div>
      
      <div className="custom-scrollbar flex min-h-0 flex-1 flex-col gap-6 overflow-y-auto overscroll-contain pr-1 lg:flex-row lg:overflow-hidden lg:pr-0">
        {/* PDF Viewer */}
        <div className="h-[55vh] min-h-72 w-full shrink-0 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] shadow-[var(--shadow-sm)] lg:h-full lg:w-[65%]">
          {signedDocument?.error ? (
            <div role="alert" className="flex h-full min-h-72 flex-col items-center justify-center gap-3 p-6 text-center">
              <div className="flex h-11 w-11 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--danger-muted)] text-[var(--danger)]">
                <FileText size={20} aria-hidden="true" />
              </div>
              <div className="max-w-sm space-y-1">
                <h2 className="text-section-heading text-[var(--text-primary)]">PDF unavailable</h2>
                <p className="text-body text-[var(--text-secondary)]">{signedDocument.error}</p>
              </div>
            </div>
          ) : signedDocument?.url ? (
            <PdfViewer url={signedDocument.url} />
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

        {/* Document Details Sidebar */}
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
