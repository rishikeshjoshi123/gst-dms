import 'server-only'

import { getCurrentOrgId } from '@/lib/actions/org'
import { createClient } from '@/lib/supabase/server'
import type { Database } from '@/lib/supabase/database.types'
import { relationshipAuthoringContextSchema } from './relationship-authoring'
import {
  clampMatterFilesOffset,
  compareSupportingFilesNewestFirst,
  isActiveSupportingFileCandidate,
  normalizeMatterFilesPage,
  paginateMatterFiles,
  type MatterFilesPageRequest,
} from './workspace-files-page'
import {
  normalizeMatterTimelinePage,
  shapeMatterTimelineRelationships,
  type MatterTimelineChronologyItem,
  type MatterTimelineChronologyPage,
  type MatterTimelinePageRequest,
  type MatterTimelineRelationshipProjection,
} from './workspace-timeline-page'
import {
  layoutMatterTimelineGraph,
  shapeMatterTimelineGraphRelationshipProjection,
  type MatterTimelineGraphLayout,
} from './matter-timeline-graph-layout'

export type { MatterTimelineChronologyItem, MatterTimelineChronologyPage, MatterTimelineRelationship, MatterTimelineRelationshipProjection } from './workspace-timeline-page'
export type { MatterTimelineGraphLayout } from './matter-timeline-graph-layout'

export type MatterTimelineGraphProjection = {
  outcome: 'ok' | 'unavailable'
  reason: 'read' | 'capacity' | 'inconsistent' | 'layout' | null
  layout: MatterTimelineGraphLayout | null
  total: number
  unfilteredTotal: number
  sourceRevision: string | null
  relationshipSourceRevision: string | null
  fetchedAt: string
}

export type MatterWorkspaceDocument = Database['public']['Tables']['documents']['Row']
export type MatterWorkspaceLink = Database['public']['Tables']['document_links']['Row']
const SUPPORTING_FILE_SELECT = [
  'id',
  'org_id',
  'matter_id',
  'document_class',
  'record_state',
  'deleted_at',
  'display_title',
  'effective_filename',
  'document_category',
  'reference_number',
  'content_availability',
  'created_at',
  'effective_size_bytes',
  'lifecycle_revision',
].join(', ')

type SupportingFileInternalRow = Pick<MatterWorkspaceDocument,
  | 'id'
  | 'org_id'
  | 'matter_id'
  | 'document_class'
  | 'record_state'
  | 'deleted_at'
  | 'display_title'
  | 'effective_filename'
  | 'document_category'
  | 'reference_number'
  | 'content_availability'
  | 'created_at'
  | 'effective_size_bytes'
  | 'lifecycle_revision'
>

export type MatterSupportingFileSummary = Omit<SupportingFileInternalRow,
  | 'org_id'
  | 'record_state'
  | 'deleted_at'
  | 'lifecycle_revision'
  | 'content_availability'
  | 'effective_size_bytes'
> & {
  content_availability: SupportingFileInternalRow['content_availability'] | null
  effective_size_bytes: number | null
  revision: number | null
}

export type MatterSupportingFilesPage = {
  items: MatterSupportingFileSummary[]
  total: number
  offset: number
  limit: number
  fetchedAt: string
  /** No collection revision exists yet; item revisions and fetchedAt are authoritative. */
  sourceRevision: null
}

function projectSupportingFile(row: SupportingFileInternalRow): MatterSupportingFileSummary {
  return {
    id: row.id,
    matter_id: row.matter_id,
    document_class: row.document_class,
    display_title: row.display_title,
    effective_filename: row.effective_filename,
    document_category: row.document_category,
    reference_number: row.reference_number,
    content_availability: row.content_availability,
    created_at: row.created_at,
    effective_size_bytes: row.effective_size_bytes,
    revision: row.lifecycle_revision,
  }
}

function activeSupportingFilesQuery(
  supabase: Awaited<ReturnType<typeof createClient>>,
  matterId: string,
  orgId: string,
  exactCount: boolean,
) {
  const query = exactCount
    ? supabase.from('documents').select(SUPPORTING_FILE_SELECT, { count: 'exact' })
    : supabase.from('documents').select(SUPPORTING_FILE_SELECT)

  return query
    .eq('org_id', orgId)
    .eq('matter_id', matterId)
    .eq('document_class', 'supporting')
    .eq('record_state', 'active')
    .is('deleted_at', null)
}

function assertSupportingFileRows(
  rows: SupportingFileInternalRow[],
  scope: { orgId: string; matterId: string; selectedId?: string },
) {
  if (rows.some((row) => !isActiveSupportingFileCandidate(row, scope))) {
    throw new Error('Unable to load the supporting document section.')
  }
}

async function readActiveMatterDocuments(
  matterId: string,
  documentClass: 'proceeding' | 'supporting',
) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  let query = supabase
    .from('documents')
    .select('*')
    .eq('matter_id', matterId)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)

  query = documentClass === 'proceeding'
    ? query.or('document_class.eq.proceeding,document_class.is.null')
    : query.eq('document_class', documentClass)

  const { data, error } = await query
    .order('created_at', { ascending: false })

  if (error) throw new Error(`Unable to load the ${documentClass} document section.`)
  return data ?? []
}

export type MatterWorkspaceCapabilities = {
  canContribute: boolean
  canCloseReopen: boolean
}

export async function readMatterRelationshipAuthoringContext(matterId: string) {
  const client = await createClient()
  const { data, error } = await client.rpc('read_matter_relationship_authoring_context', { p_matter_id: matterId })
  if (error) return null
  const parsed = relationshipAuthoringContextSchema.safeParse(data?.[0])
  return parsed.success ? parsed.data : null
}

/** Server-derived UI capabilities; clients never infer permissions from role names. */
export async function readMatterWorkspaceCapabilities(): Promise<MatterWorkspaceCapabilities> {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { canContribute: false, canCloseReopen: false }

  const { data, error } = await supabase.rpc('get_my_organisation_context')
  if (error) return { canContribute: false, canCloseReopen: false }
  const context = (data ?? []).find((row) => row.org_id === orgId && row.state === 'active')
  return {
    canContribute: Boolean(context?.capabilities.includes('document.intake.create')),
    canCloseReopen: Boolean(context?.is_owner || context?.role === 'admin'),
  }
}

/**
 * The Timeline inspector reads only notes attached to its already-authorised
 * selected document. It deliberately avoids the Notes workspace's member
 * directory and task-summary projections.
 */
export async function readSelectedDocumentNotePreview(matterId: string, documentId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data: selectedDocument, error: documentError } = await supabase
    .from('documents')
    .select('id')
    .eq('id', documentId)
    .eq('org_id', orgId)
    .eq('matter_id', matterId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .or('document_class.eq.proceeding,document_class.is.null')
    .maybeSingle()
  if (documentError) throw new Error('Unable to validate the selected proceeding for notes.')
  if (!selectedDocument) return []

  const { data, error } = await supabase
    .from('case_notes')
    .select('id, content, created_at, author_id')
    .eq('org_id', orgId)
    .eq('matter_id', matterId)
    .eq('document_id', documentId)
    .is('deleted_at', null)
    .order('is_pinned', { ascending: false })
    .order('created_at', { ascending: false })
    .order('id', { ascending: true })
    .limit(5)
  if (error) throw new Error('Unable to load selected-document notes.')

  return (data ?? []).map((note) => ({
    id: note.id,
    content: note.content,
    created_at: note.created_at,
    authorLabel: null,
  }))
}

/** Timeline deliberately excludes supporting and cross-matter documents. */
export function readActiveProceedings(matterId: string) {
  return readActiveMatterDocuments(matterId, 'proceeding')
}

/** The only live Timeline reader. The RPC owns actor, matter, lifecycle, version and selection fences. */
export async function readMatterTimelineChronology(
  matterId: string,
  request: MatterTimelinePageRequest = {},
  selectedDocumentId: string | null = null,
): Promise<MatterTimelineChronologyPage> {
  const normalized = normalizeMatterTimelinePage(request)
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('read_matter_timeline_chronology', {
    p_matter_id: matterId,
    p_offset: normalized.offset,
    p_limit: normalized.limit,
    p_filters: normalized.filters,
    p_selected_document_id: selectedDocumentId,
  })
  if (error) throw new Error('Unable to load the chronology.')
  const row = (data ?? [])[0]
  if (!row) return { outcome: 'unavailable', items: [], total: 0, unfilteredTotal: 0, offset: 0, limit: normalized.limit, fetchedAt: new Date().toISOString(), sourceRevision: null, selected: null }
  return {
    outcome: row.outcome === 'ok' ? 'ok' : 'unavailable',
    items: Array.isArray(row.items) ? row.items as MatterTimelineChronologyItem[] : [],
    total: row.total, unfilteredTotal: row.unfiltered_total, offset: row.offset, limit: row.limit,
    fetchedAt: row.fetched_at, sourceRevision: row.source_revision,
    selected: row.selected && typeof row.selected === 'object' && !Array.isArray(row.selected) ? row.selected as MatterTimelineChronologyItem : null,
  }
}

/** Selected-document relationship inspection uses only the governed effective projection. */
export async function readMatterTimelineRelationships(
  matterId: string,
  selectedDocumentId: string | null = null,
): Promise<MatterTimelineRelationshipProjection> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('read_matter_timeline_relationships', {
    p_matter_id: matterId,
    p_selected_document_id: selectedDocumentId ?? undefined,
  })
  if (error) throw new Error('Unable to load selected-document relationships.')
  const row = (data ?? [])[0]
  if (!row || row.outcome !== 'ok') {
    return {
      outcome: 'unavailable', relationships: [], sourceRevision: null,
      fetchedAt: row?.fetched_at ?? new Date().toISOString(),
    }
  }
  return {
    outcome: 'ok',
    relationships: shapeMatterTimelineRelationships(row.relationships),
    sourceRevision: row.source_revision,
    fetchedAt: row.fetched_at,
  }
}

async function readMatterTimelineGraphRelationships(
  matterId: string,
): Promise<MatterTimelineRelationshipProjection> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('read_matter_timeline_relationships', {
    p_matter_id: matterId,
    p_selected_document_id: undefined,
  })
  if (error) throw new Error('Unable to load timeline graph relationships.')
  const shaped = shapeMatterTimelineGraphRelationshipProjection((data ?? [])[0])
  if (shaped.outcome !== 'ok') {
    return {
      outcome: 'unavailable', relationships: [], sourceRevision: null,
      fetchedAt: new Date().toISOString(),
    }
  }
  return {
    outcome: 'ok', relationships: shaped.relationships, sourceRevision: shaped.sourceRevision,
    fetchedAt: shaped.fetchedAt,
  }
}

/**
 * The graph composes only the two secured projections. It never queries
 * relationship tables, legacy links, candidates, or document metadata itself.
 */
export async function readMatterTimelineGraph(
  matterId: string,
  request: MatterTimelinePageRequest = {},
): Promise<MatterTimelineGraphProjection> {
  const normalized = normalizeMatterTimelinePage(request)
  const unavailable = (
    reason: Exclude<MatterTimelineGraphProjection['reason'], null>,
    total = 0,
    unfilteredTotal = 0,
  ): MatterTimelineGraphProjection => ({
    outcome: 'unavailable', reason, layout: null, total, unfilteredTotal,
    sourceRevision: null, relationshipSourceRevision: null,
    fetchedAt: new Date().toISOString(),
  })

  try {
    const first = await readMatterTimelineChronology(matterId, { ...normalized, offset: 0, limit: 100 })
    if (first.outcome !== 'ok') return unavailable('read')
    if (first.total > 250) return unavailable('capacity', first.total, first.unfilteredTotal)

    const offsets = [100, 200].filter((offset) => offset < first.total)
    const [remaining, relationships] = await Promise.all([
      Promise.all(offsets.map((offset) => readMatterTimelineChronology(
        matterId,
        { ...normalized, offset, limit: 100 },
      ))),
      readMatterTimelineGraphRelationships(matterId),
    ])
    if (relationships.outcome !== 'ok') return unavailable('read')
    const pages = [first, ...remaining]
    if (pages.some((page, index) => (
      page.outcome !== 'ok'
      || page.offset !== index * 100
      || page.total !== first.total
      || page.unfilteredTotal !== first.unfilteredTotal
      || page.sourceRevision !== first.sourceRevision
    ))) return unavailable('inconsistent', first.total, first.unfilteredTotal)

    const documents = pages.flatMap((page) => page.items)
    if (documents.length !== first.total || new Set(documents.map((document) => document.id)).size !== documents.length) {
      return unavailable('inconsistent', first.total, first.unfilteredTotal)
    }
    if (documents.some((document) => document.classificationState !== 'canonical')) {
      return unavailable('inconsistent', first.total, first.unfilteredTotal)
    }
    try {
      return {
        outcome: 'ok', reason: null,
        layout: layoutMatterTimelineGraph(documents, relationships.relationships),
        total: first.total, unfilteredTotal: first.unfilteredTotal,
        sourceRevision: first.sourceRevision,
        relationshipSourceRevision: relationships.sourceRevision,
        fetchedAt: first.fetchedAt,
      }
    } catch {
      return unavailable('layout', first.total, first.unfilteredTotal)
    }
  } catch {
    return unavailable('read')
  }
}

/** Files reads one exact, bounded active-supporting page without browser storage data. */
export async function readActiveSupportingFiles(
  matterId: string,
  request: MatterFilesPageRequest = {},
): Promise<MatterSupportingFilesPage> {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  const normalized = normalizeMatterFilesPage(request)
  if (!orgId) {
    return {
      items: [],
      total: 0,
      ...normalized,
      fetchedAt: new Date().toISOString(),
      sourceRevision: null,
    }
  }
  const authorizedOrgId = orgId

  async function readPage(offset: number) {
    const { data, error, count } = await activeSupportingFilesQuery(
      supabase,
      matterId,
      authorizedOrgId,
      true,
    )
      .order('created_at', { ascending: false })
      .order('id', { ascending: false })
      .range(offset, offset + normalized.limit - 1)

    if (error || count === null) throw new Error('Unable to load the supporting document section.')
    const rows = (data ?? []) as unknown as SupportingFileInternalRow[]
    assertSupportingFileRows(rows, { orgId: authorizedOrgId, matterId })
    return { rows, total: count }
  }

  let offset = normalized.offset
  let result = await readPage(offset)
  // A stale or hostile overflow offset is moved to the last page. Re-read so
  // its rows and exact total come from the same database statement.
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const clamped = clampMatterFilesOffset(offset, normalized.limit, result.total)
    if (clamped === offset) break
    offset = clamped
    result = await readPage(offset)
  }

  return {
    items: result.rows.map(projectSupportingFile),
    total: result.total,
    offset,
    limit: normalized.limit,
    fetchedAt: new Date().toISOString(),
    sourceRevision: null,
  }
}

/** Validate an off-page Files selection under exactly the page reader's fences. */
export async function readActiveSupportingFileSelection(matterId: string, documentId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return null

  const { data, error } = await activeSupportingFilesQuery(supabase, matterId, orgId, false)
    .eq('id', documentId)
    .maybeSingle()
  if (error) throw new Error('Unable to load the selected supporting document.')
  if (!data) return null

  const row = data as unknown as SupportingFileInternalRow
  assertSupportingFileRows([row], { orgId, matterId, selectedId: documentId })
  return projectSupportingFile(row)
}

/** Trash uses its already-authorised exact snapshot and never issues an active read. */
export function createSupportingFilesSnapshotPage(
  documents: readonly Pick<MatterWorkspaceDocument,
    | 'id'
    | 'matter_id'
    | 'document_class'
    | 'display_title'
    | 'effective_filename'
    | 'document_category'
    | 'reference_number'
    | 'created_at'
  >[],
  request: MatterFilesPageRequest = {},
): MatterSupportingFilesPage {
  const supporting = documents
    .filter((document) => document.document_class === 'supporting')
    .sort(compareSupportingFilesNewestFirst)
  const page = paginateMatterFiles(supporting, request)
  return {
    ...page,
    items: page.items.map((document) => ({
      ...document,
      content_availability: null,
      effective_size_bytes: null,
      revision: null,
    })),
    fetchedAt: new Date().toISOString(),
    sourceRevision: null,
  }
}

/** Notes needs only safe, same-matter option identity rather than full document rows. */
export async function readActiveNoteDocumentOptions(matterId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data, error } = await supabase
    .from('documents')
    .select('id, matter_id, reference_number, display_title, effective_filename')
    .eq('matter_id', matterId)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .order('created_at', { ascending: false })

  if (error) throw new Error('Unable to load note document options.')
  return data ?? []
}

/**
 * Transitional adapter for legacy document_links. It accepts the already
 * authorised proceeding set and rejects every edge whose two endpoints are not
 * both in that exact set. It never follows an endpoint into another matter.
 */
export async function readTransitionalTimelineLinks(
  proceedingIds: readonly string[],
): Promise<MatterWorkspaceLink[]> {
  const ids = [...new Set(proceedingIds)]
  if (ids.length === 0) return []

  const supabase = await createClient()
  const { data, error } = await supabase
    .from('document_links')
    .select('*')
    .in('from_doc_id', ids)

  if (error) throw new Error('Unable to load the transitional Timeline relationships.')
  const allowedIds = new Set(ids)
  return (data ?? []).filter((link) => (
    allowedIds.has(link.from_doc_id)
    && typeof link.to_doc_id === 'string'
    && allowedIds.has(link.to_doc_id)
  ))
}
