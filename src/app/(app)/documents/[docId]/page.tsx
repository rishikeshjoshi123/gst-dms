import Link from 'next/link'
import { notFound } from 'next/navigation'
import { ArrowLeft } from 'lucide-react'

import { CanonicalDocumentWorkbench } from '@/components/documents/CanonicalDocumentWorkbench'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { TrashReadOnlyStrip } from '@/components/trash/TrashReadOnlyStrip'
import { pdfSourceFailureFromAccessCode } from '@/components/ui/pdf-viewer-model'
import {
  getCanonicalDocumentVersionSignedUrl,
  getDocumentsByMatter,
  getDocumentAttachmentState,
} from '@/lib/actions/document'
import { parseCanonicalDocumentUrlState, safeMatterReturnPath } from '@/lib/canonical-document-route'
import { getNotes } from '@/lib/actions/notes'
import { documentInspectorIds } from '@/lib/documents/document-inspector-ids'
import { getDocumentInspectorMetadata } from '@/lib/documents/inspector-effective-metadata'
import { shapeDocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'
import { getCanonicalAssignedDocument } from '@/lib/trash/exact-resource'
import { readMatterWorkspaceCapabilities } from '@/lib/matters/workspace-read'

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
  const canRepairBoundary = !isTrashReadOnly && (await readMatterWorkspaceCapabilities()).canContribute
  const doc = isTrashReadOnly ? exactDocument.data.record : exactDocument.record
  const canAttachPdf = !isTrashReadOnly && !doc.current_version_id && sourceLocator.sourceState !== 'invalid' && !sourceLocator.versionId
    ? (await getDocumentAttachmentState(docId))?.eligible === true
    : false
  const matterId = doc.matter_id
  const matterReturnPath = safeMatterReturnPath(sourceLocator.returnTo, matterId) ?? `/matters/${matterId}`

  const sourcePage = sourceLocator.page ?? 1
  const selectedVersionId = sourceLocator.sourceState === 'invalid'
    ? null
    : sourceLocator.versionId ?? doc.current_version_id
  const signedDocument = selectedVersionId
    ? await getCanonicalDocumentVersionSignedUrl(
      docId,
      selectedVersionId,
      isTrashReadOnly ? exactDocument.expectedMatterId : undefined,
      sourcePage,
    )
    : null
  const signedDocumentFailure = sourceLocator.sourceState === 'invalid'
    ? 'unavailable' as const
    : signedDocument && signedDocument.code !== 'ok'
      ? pdfSourceFailureFromAccessCode(signedDocument.code)
      : undefined
  const signedDocumentUrl = signedDocument && 'url' in signedDocument ? signedDocument.url : null
  const source = signedDocument && 'versionId' in signedDocument ? {
    versionId: signedDocument.versionId,
    versionNumber: signedDocument.versionNumber,
    pageCount: signedDocument.pageCount,
    isCurrent: signedDocument.isCurrent,
    page: sourcePage,
  } : null
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
    { label: doc.matters?.title || 'Matter', href: matterReturnPath },
    { label: documentTitle },
  ]

  return (
    <div className="flex w-full flex-1 animate-fade-in flex-col gap-4 overflow-hidden">
      <BreadcrumbSetter breadcrumbs={breadcrumbs} />
      {isTrashReadOnly && <TrashReadOnlyStrip context={exactDocument.context} />}

      <div className="flex shrink-0 items-center gap-4">
        <Link
          href={matterReturnPath}
          className="flex min-h-11 items-center gap-2 text-sm text-[var(--text-muted)] transition-colors hover:text-[var(--text-primary)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
        >
          <ArrowLeft size={16} aria-hidden="true" />
          Back to Matter
        </Link>
      </div>

      <CanonicalDocumentWorkbench
        doc={doc}
        allDocuments={allDocuments}
        links={links ?? []}
        notes={notes}
        effectiveMetadata={inspectorMetadata[doc.id]}
        inspectorMetadataByDocumentId={inspectorMetadata}
        source={source}
        sourceUrl={signedDocumentUrl ?? null}
        sourceFailure={signedDocumentFailure}
        expectedMatterId={isTrashReadOnly ? exactDocument.expectedMatterId : undefined}
        readOnly={isTrashReadOnly}
        canAttachPdf={canAttachPdf}
        canRepairBoundary={canRepairBoundary}
      />
    </div>
  )
}
