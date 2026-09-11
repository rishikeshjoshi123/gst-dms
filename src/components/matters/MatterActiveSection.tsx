import { getNotes } from '@/lib/actions/notes'
import { getWikiSections } from '@/lib/actions/wiki'
import { getDocumentInspectorMetadata } from '@/lib/documents/inspector-effective-metadata'
import { shapeDocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'
import {
  createSupportingFilesSnapshotPage,
  readActiveNoteDocumentOptions,
  readMatterTimelineChronology,
  readMatterTimelineRelationships,
  readSelectedDocumentNotePreview,
  readActiveSupportingFileSelection,
  readActiveSupportingFiles,
} from '@/lib/matters/workspace-read'
import { createMatterTimelineSnapshotPage, shapeMatterTimelineSnapshotMetadata } from '@/lib/matters/workspace-timeline-page'
import { acceptedSectionSelection } from '@/lib/matters/workspace-selection'
import type { MatterWorkspaceRouteState } from '@/lib/matters/workspace-route'
import { getOperationalMemberOptions } from '@/lib/organisation/member-directory'
import { getExactMatter } from '@/lib/trash/exact-resource'
import { CaseWikiTab } from './CaseWikiTab'
import { MatterDetailsTab } from './MatterDetailsTab'
import { MatterFilesSection } from './MatterFilesSection'
import { MatterNotesTab } from './MatterNotesTab'
import { MatterTimelineChronology } from './MatterTimelineChronology'
import { MatterUnavailableSection } from './MatterUnavailableSection'

type ExactMatter = NonNullable<Awaited<ReturnType<typeof getExactMatter>>>

async function TimelineSection({
  matterId,
  exactMatter,
  route,
  queryEntries,
}: ActiveSectionProps) {
  const isTrash = exactMatter.state === 'trash'
  const trashMetadataByDocumentId = isTrash
    ? shapeMatterTimelineSnapshotMetadata(
        exactMatter.data.documents
          .filter((document) => document.matter_id === matterId && (document.document_class === 'proceeding' || document.document_class === null))
          .map((document) => document.id),
        exactMatter.data.inspectorMetadataRows,
      )
    : {}
  const page = isTrash
    ? createMatterTimelineSnapshotPage(matterId, exactMatter.data.documents, trashMetadataByDocumentId, route.timelinePage, route.selectedDocumentId)
    : await readMatterTimelineChronology(matterId, route.timelinePage, route.selectedDocumentId)
  const notePreview = page.selected && route.inspector === 'notes'
    ? isTrash
      ? exactMatter.data.notes
          .filter((note) => note.document_id === page.selected?.id)
          .slice(0, 5)
          .map((note) => ({ id: note.id, content: note.content, created_at: note.created_at, authorLabel: null }))
      : await readSelectedDocumentNotePreview(matterId, page.selected.id)
    : []
  const relationshipProjection = page.selected && route.inspector === 'relationships' && !isTrash
    ? await readMatterTimelineRelationships(matterId, page.selected.id)
    : { outcome: 'ok' as const, relationships: [], sourceRevision: null, fetchedAt: page.fetchedAt }

  return (
    <div className="flex h-full min-h-0 flex-col gap-2 pt-2 md:pt-3">
      <MatterTimelineChronology matterId={matterId} page={page} selectionUnavailable={route.selectionRequested && !page.selected} queryEntries={queryEntries} filters={route.timelinePage.filters} inspector={route.inspector} notePreview={notePreview} relationshipProjection={relationshipProjection} />
    </div>
  )
}

async function FilesSection({ matterId, exactMatter, route, queryEntries }: ActiveSectionProps) {
  const readOnly = exactMatter.state === 'trash'
  const page = readOnly
    ? createSupportingFilesSnapshotPage(exactMatter.data.documents, route.filesPage)
    : await readActiveSupportingFiles(matterId, route.filesPage)
  const accepted = readOnly
    ? acceptedSectionSelection(
        route.selectedDocumentId,
        matterId,
        'supporting',
        exactMatter.data.documents,
      )
    : route.selectedDocumentId
      ? await readActiveSupportingFileSelection(matterId, route.selectedDocumentId)
      : null
  const selectionUnavailable = route.selectionRequested && !accepted
  const inspectorMetadataByDocumentId = accepted
    ? readOnly
      ? shapeDocumentInspectorMetadata([accepted.id], exactMatter.data.inspectorMetadataRows)
      : await getDocumentInspectorMetadata([accepted.id])
    : {}

  return (
    <MatterFilesSection
      matterId={matterId}
      page={page}
      selectedDocument={accepted}
      selectedDocumentId={accepted?.id ?? null}
      selectionUnavailable={selectionUnavailable}
      inspectorMetadata={accepted ? inspectorMetadataByDocumentId[accepted.id] : undefined}
      inspector={route.inspector}
      queryEntries={queryEntries}
    />
  )
}

async function CaseBriefSection({ matterId, exactMatter, canContribute }: ActiveSectionProps) {
  const isTrash = exactMatter.state === 'trash'
  const readOnly = isTrash || !canContribute
  const sections = isTrash ? exactMatter.data.wikiSections : await getWikiSections(matterId)
  return <CaseWikiTab matterId={matterId} initialSections={sections} readOnly={readOnly} />
}

async function NotesSection({ matterId, exactMatter, canContribute }: ActiveSectionProps) {
  const isTrash = exactMatter.state === 'trash'
  const readOnly = isTrash || !canContribute
  if (isTrash) {
    const documents = exactMatter.data.documents.map((document) => ({
      id: document.id,
      matter_id: document.matter_id,
      reference_number: document.reference_number,
      display_title: document.display_title,
      effective_filename: document.effective_filename,
    }))
    return (
      <MatterNotesTab
        matterId={matterId}
        initialNotes={exactMatter.data.notes}
        documents={documents}
        users={[]}
        readOnly
      />
    )
  }

  const [notes, documents, users] = await Promise.all([
    getNotes({ matterId }),
    readActiveNoteDocumentOptions(matterId),
    getOperationalMemberOptions(),
  ])
  return <MatterNotesTab matterId={matterId} initialNotes={notes} documents={documents} users={users} readOnly={readOnly} />
}

function DetailsSection({ exactMatter, canContribute, canCloseReopen }: ActiveSectionProps) {
  const isTrash = exactMatter.state === 'trash'
  const record = isTrash ? exactMatter.data.record : exactMatter.record
  const readOnly = isTrash || !canContribute || (record.work_state === 'closed' && !canCloseReopen)
  const matter = {
    ...record,
    client_id: record.client_id ?? null,
    matter_code: record.matter_code ?? null,
    financial_year: record.financial_year ?? null,
    description: record.description ?? null,
    revision: 'revision' in record && typeof record.revision === 'number' ? record.revision : 0,
  }
  return <MatterDetailsTab matter={matter} readOnly={readOnly} canCloseReopen={canCloseReopen} />
}

type ActiveSectionProps = {
  matterId: string
  exactMatter: ExactMatter
  route: MatterWorkspaceRouteState
  queryEntries: Array<[string, string]>
  canContribute: boolean
  canCloseReopen: boolean
}

export async function MatterActiveSection(props: ActiveSectionProps) {
  switch (props.route.section) {
    case 'timeline':
      return <TimelineSection {...props} />
    case 'files':
      return <FilesSection {...props} />
    case 'case-brief':
      return <CaseBriefSection {...props} />
    case 'notes':
      return <NotesSection {...props} />
    case 'deadlines':
      return (
        <MatterUnavailableSection title="Deadlines are not available in this release">
          Use the owning Deadlines workspace for deadline review and attention states.
        </MatterUnavailableSection>
      )
    case 'financials':
      return (
        <MatterUnavailableSection title="Financials are not available in this release">
          This Matter workspace does not yet provide a canonical financial projection.
        </MatterUnavailableSection>
      )
    case 'activity':
      return (
        <MatterUnavailableSection title="Activity is not available in this release">
          Use the owning Activity workspace for the canonical organisation activity stream.
        </MatterUnavailableSection>
      )
    case 'details':
      return <DetailsSection {...props} />
  }
}
