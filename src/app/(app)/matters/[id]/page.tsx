import { MATTER_STATUS_LABELS } from '@/lib/constants'
import { getDocumentsByMatter } from '@/lib/actions/document'
import { getWikiSections } from '@/lib/actions/wiki'
import { getNotes } from '@/lib/actions/notes'
import { getDocumentInspectorMetadata } from '@/lib/documents/inspector-effective-metadata'
import { shapeDocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'
import { getExactMatter } from '@/lib/trash/exact-resource'
import { notFound } from 'next/navigation'
import { AlertTriangle } from 'lucide-react'
import { MatterTabs } from '@/components/matters/MatterTabs'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { TrashReadOnlyStrip } from '@/components/trash/TrashReadOnlyStrip'
import { getOperationalMemberOptions } from '@/lib/organisation/member-directory'

export const metadata = { title: 'Matter Workspace — GST Litigation DMS' }

export default async function MatterPage(props: { 
  params: Promise<{ id: string }>
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const params = await props.params;
  const searchParams = await props.searchParams;
  const fromReview = searchParams?.from === 'review'
  const exactMatter = await getExactMatter(params.id)

  if (!exactMatter) notFound()
  const isTrashReadOnly = exactMatter.state === 'trash'
  const matter = isTrashReadOnly ? exactMatter.data.record : exactMatter.record

  const trashDocuments = isTrashReadOnly ? exactMatter.data.documents : []
  const activeDocuments = isTrashReadOnly ? null : await getDocumentsByMatter(params.id)
  const proceedings = isTrashReadOnly
    ? trashDocuments.filter((document) => document.document_class === 'proceeding' || !document.document_class)
    : activeDocuments!.proceedings
  const supporting = isTrashReadOnly
    ? trashDocuments.filter((document) => document.document_class === 'supporting')
    : activeDocuments!.supporting
  const links = isTrashReadOnly ? exactMatter.data.links : activeDocuments!.links
  const wikiSections = isTrashReadOnly ? exactMatter.data.wikiSections : await getWikiSections(params.id)
  const notes = isTrashReadOnly ? exactMatter.data.notes : await getNotes({ matterId: params.id })
  const documentIds = [...proceedings.map((document) => document.id), ...supporting.map((document) => document.id)]
  const inspectorMetadataByDocumentId = isTrashReadOnly
    ? shapeDocumentInspectorMetadata(documentIds, exactMatter.data.inspectorMetadataRows)
    : await getDocumentInspectorMetadata(documentIds)

  const usersList = isTrashReadOnly ? [] : await getOperationalMemberOptions()

  const isClosed = matter.status === 'closed'

  const breadcrumbs = fromReview
    ? [
        { label: 'Pending Review', href: '/review' },
        { label: matter.clients?.name || 'Unknown', href: `/clients/${matter.client_id}` },
        { label: matter.title }
      ]
    : [
        { label: 'Clients', href: '/clients' },
        { label: matter.clients?.name || 'Unknown', href: `/clients/${matter.client_id}` },
        { label: matter.title }
      ]

  return (
    <div className="flex flex-col flex-1 overflow-hidden h-full animate-fade-in -mt-2 ">
      <BreadcrumbSetter breadcrumbs={breadcrumbs} />
      {isTrashReadOnly && <TrashReadOnlyStrip context={exactMatter.context} />}

      {/* Warning Banner */}
      {!isTrashReadOnly && isClosed && (
        <div className="flex items-center gap-3 p-3 mb-4 rounded-[var(--radius-md)] bg-[var(--danger-muted)] border border-[color-mix(in_srgb,var(--danger)_30%,transparent)] text-[var(--danger)] shadow-[var(--shadow-sm)] shrink-0">
          <AlertTriangle size={18} />
          <p className="text-[14px] font-medium">This matter is marked as {MATTER_STATUS_LABELS[matter.status]}. Uploading new documents is disabled.</p>
        </div>
      )}

      <MatterTabs
        matter={matter}
        proceedings={proceedings}
        supporting={supporting}
        links={links || []}
        wikiSections={wikiSections || []}
        notes={notes || []}
        users={usersList}
        inspectorMetadataByDocumentId={inspectorMetadataByDocumentId}
        readOnly={isTrashReadOnly}
      />
    </div>
  )
}
