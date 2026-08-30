import { getDocumentVersionSignedUrl, getDocumentsByMatter } from '@/lib/actions/document'
import { getNotes } from '@/lib/actions/notes'
import { getDocumentInspectorMetadata } from '@/lib/documents/inspector-effective-metadata'
import { documentInspectorIds } from '@/lib/documents/document-inspector-ids'
import { notFound } from 'next/navigation'
import { PdfViewer } from '@/components/ui/pdf-viewer'
import { TimelineDocumentDetail } from '@/components/matters/TimelineDocumentDetail'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import Link from 'next/link'
import { ArrowLeft, FileText } from 'lucide-react'
import { getExactDocument } from '@/lib/trash/exact-resource'

export default async function DocumentPage(props: { params: Promise<{ id: string; docId: string }> }) {
  const params = await props.params;
  const exactDocument = await getExactDocument(params.id, params.docId)
  // Trash rendering/action suppression is a later tranche. Keep this route
  // closed until that work can safely make its existing mutations read-only.
  if (!exactDocument || exactDocument.state !== 'active') {
    notFound()
  }
  const doc = exactDocument.record

  const signedDocument = doc.current_version_id
    ? await getDocumentVersionSignedUrl(doc.current_version_id)
    : null
  const notes = await getNotes({ documentId: params.docId })
  const allDocsData = await getDocumentsByMatter(params.id)
  const allDocuments = [...allDocsData.proceedings, ...allDocsData.supporting]
  const links = allDocsData.links
  const inspectorMetadata = await getDocumentInspectorMetadata(documentInspectorIds(doc.id, allDocuments))
  
  if (signedDocument && (signedDocument.error || !signedDocument.url)) {
    return <div className="p-10 text-[var(--danger)]">Failed to load document: {signedDocument.error}</div>
  }

  const storageFilename = doc.storage_path?.split('/').pop()
  const effectiveDocument = inspectorMetadata[doc.id]
  const documentTitle = effectiveDocument?.state === 'available'
    ? effectiveDocument.referenceNumber || doc.display_title || storageFilename || 'Document (reference unavailable)'
    : doc.display_title || storageFilename || 'Document'

  const breadcrumbs = [
    { label: 'Clients', href: '/clients' },
    { label: doc.matters?.title || 'Matter', href: `/matters/${params.id}` },
    { label: documentTitle }
  ]

  return (
    <div className="flex flex-col flex-1 overflow-hidden gap-4 w-full animate-fade-in">
      <BreadcrumbSetter breadcrumbs={breadcrumbs} />

      <div className="flex items-center gap-4 shrink-0">
        <Link href={`/matters/${params.id}`} className="flex items-center gap-2 text-sm text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors">
          <ArrowLeft size={16} />
          Back to Matter
        </Link>
      </div>
      
      <div className="flex flex-col lg:flex-row gap-6 min-h-0 flex-1">
        {/* PDF Viewer */}
        <div className="w-full lg:w-[65%] h-full rounded-[var(--radius-md)] border border-[var(--border)] shadow-[var(--shadow-sm)] overflow-hidden bg-[var(--surface)]">
          {signedDocument?.url ? (
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
        <div className="w-full lg:w-[35%] h-full">
          <TimelineDocumentDetail
            doc={doc}
            allDocuments={allDocuments}
            links={links}
            notes={notes}
            effectiveMetadata={inspectorMetadata[doc.id]}
            inspectorMetadataByDocumentId={inspectorMetadata}
          />
        </div>
      </div>
    </div>
  )
}
