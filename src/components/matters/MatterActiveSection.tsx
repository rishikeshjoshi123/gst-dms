import { getNotes } from '@/lib/actions/notes'
import { getWikiSections } from '@/lib/actions/wiki'
import { getDocumentInspectorMetadata } from '@/lib/documents/inspector-effective-metadata'
import { shapeDocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'
import {
  readActiveNoteDocumentOptions,
  readActiveProceedings,
  readActiveSupportingFiles,
  readSelectedDocumentNotes,
  readTransitionalTimelineLinks,
} from '@/lib/matters/workspace-read'
import { acceptedSectionSelection } from '@/lib/matters/workspace-selection'
import type { MatterWorkspaceRouteState } from '@/lib/matters/workspace-route'
import { getOperationalMemberOptions } from '@/lib/organisation/member-directory'
import { getExactMatter } from '@/lib/trash/exact-resource'
import { CaseWikiTab } from './CaseWikiTab'
import { MatterDetailsTab } from './MatterDetailsTab'
import { MatterFilesSection } from './MatterFilesSection'
import { MatterNotesTab } from './MatterNotesTab'
import { MatterTimelineTab } from './MatterTimelineTab'
import { MatterUnavailableSection } from './MatterUnavailableSection'

type ExactMatter = NonNullable<Awaited<ReturnType<typeof getExactMatter>>>

function unavailableSelection() {
  return (
    <div role="status" className="shrink-0 border border-[var(--border)] bg-[var(--surface)] p-4 text-sm text-[var(--text-secondary)]">
      The selected document is unavailable. Choose a document from this matter.
    </div>
  )
}

async function TimelineSection({
  matterId,
  exactMatter,
  route,
  queryEntries,
  canContribute,
}: ActiveSectionProps) {
  const isTrash = exactMatter.state === 'trash'
  const record = isTrash ? exactMatter.data.record : exactMatter.record
  const readOnly = isTrash || record.status === 'closed' || !canContribute
  const documents = isTrash
    ? exactMatter.data.documents.filter((document) => document.document_class === 'proceeding' || document.document_class === null)
    : await readActiveProceedings(matterId)
  const accepted = acceptedSectionSelection(
    route.selectedDocumentId,
    matterId,
    'proceeding',
    documents.map(({ id, matter_id, document_class }) => ({ id, matter_id, document_class })),
  )
  const selectionUnavailable = route.selectionRequested && !accepted

  const links = isTrash
    ? exactMatter.data.links.filter((link) => {
        const ids = new Set(documents.map((document) => document.id))
        return ids.has(link.from_doc_id) && Boolean(link.to_doc_id && ids.has(link.to_doc_id))
      })
    : await readTransitionalTimelineLinks(documents.map((document) => document.id))

  const inspectorMetadataByDocumentId = accepted
    ? isTrash
      ? shapeDocumentInspectorMetadata([accepted.id], exactMatter.data.inspectorMetadataRows)
      : await getDocumentInspectorMetadata([accepted.id])
    : {}
  const notes = accepted && route.inspector === 'notes'
    ? isTrash
      ? exactMatter.data.notes.filter((note) => note.document_id === accepted.id)
      : await readSelectedDocumentNotes(matterId, accepted.id)
    : []

  return (
    <div className="flex h-full min-h-0 flex-col gap-2 pt-2 md:pt-3">
      {selectionUnavailable && unavailableSelection()}
      {documents.length === 0 ? (
        <MatterUnavailableSection title="No proceedings yet">
          Proceeding documents added to this matter will appear in the Timeline.
        </MatterUnavailableSection>
      ) : (
        <div className="min-h-0 flex-1">
          <MatterTimelineTab
            matterId={matterId}
            documents={documents}
            links={links}
            inspectorMetadataByDocumentId={inspectorMetadataByDocumentId}
            notes={notes}
            selectedDocumentId={accepted?.id ?? null}
            inspector={route.inspector}
            queryEntries={queryEntries}
            readOnly={readOnly}
          />
        </div>
      )}
    </div>
  )
}

async function FilesSection({ matterId, exactMatter, route, queryEntries }: ActiveSectionProps) {
  const readOnly = exactMatter.state === 'trash'
  const documents = readOnly
    ? exactMatter.data.documents.filter((document) => document.document_class === 'supporting')
    : await readActiveSupportingFiles(matterId)
  const accepted = acceptedSectionSelection(
    route.selectedDocumentId,
    matterId,
    'supporting',
    documents.map(({ id, matter_id, document_class }) => ({ id, matter_id, document_class })),
  )
  const selectionUnavailable = route.selectionRequested && !accepted
  const inspectorMetadataByDocumentId = accepted
    ? readOnly
      ? shapeDocumentInspectorMetadata([accepted.id], exactMatter.data.inspectorMetadataRows)
      : await getDocumentInspectorMetadata([accepted.id])
    : {}

  return (
    <MatterFilesSection
      matterId={matterId}
      documents={documents}
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

function DetailsSection({ exactMatter, canContribute }: ActiveSectionProps) {
  const isTrash = exactMatter.state === 'trash'
  const readOnly = isTrash || !canContribute
  const record = isTrash ? exactMatter.data.record : exactMatter.record
  const matter = {
    ...record,
    client_id: record.client_id ?? null,
    matter_code: record.matter_code ?? null,
    financial_year: record.financial_year ?? null,
    description: record.description ?? null,
    revision: 'revision' in record && typeof record.revision === 'number' ? record.revision : 0,
  }
  return <MatterDetailsTab matter={matter} readOnly={readOnly} />
}

type ActiveSectionProps = {
  matterId: string
  exactMatter: ExactMatter
  route: MatterWorkspaceRouteState
  queryEntries: Array<[string, string]>
  canContribute: boolean
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
