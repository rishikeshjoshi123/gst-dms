import { MATTER_FILES_DEFAULT_LIMIT, normalizeMatterFilesPage } from './workspace-files-page'
import { MATTER_TIMELINE_DEFAULT_LIMIT, normalizeMatterTimelinePage } from './workspace-timeline-page'

export const MATTER_SECTION_IDS = [
  'timeline',
  'files',
  'case-brief',
  'notes',
  'deadlines',
  'financials',
  'activity',
  'details',
] as const

export type MatterSectionId = (typeof MATTER_SECTION_IDS)[number]

export const MATTER_PRIMARY_MOBILE_SECTIONS = [
  'timeline',
  'files',
  'case-brief',
  'notes',
] as const satisfies readonly MatterSectionId[]

export const MATTER_SECONDARY_MOBILE_SECTIONS = [
  'deadlines',
  'financials',
  'activity',
  'details',
] as const satisfies readonly MatterSectionId[]

export const MATTER_SECTION_LABELS: Record<MatterSectionId, string> = {
  timeline: 'Timeline',
  files: 'Files',
  'case-brief': 'Case Brief',
  notes: 'Notes',
  deadlines: 'Deadlines',
  financials: 'Financials',
  activity: 'Activity',
  details: 'Details',
}

export type MatterWorkspaceSearchParams = Record<string, string | string[] | undefined>

export type MatterInspectorView = 'overview' | 'relationships' | 'notes'
export type MatterTimelineView = 'graph' | 'chronology'

export const MATTER_INSPECTOR_LABELS: Record<MatterInspectorView, string> = {
  overview: 'Overview',
  relationships: 'Relationships',
  notes: 'Notes',
}

export type MatterWorkspaceRouteState = {
  section: MatterSectionId
  timelineView: MatterTimelineView
  selectionRequested: boolean
  selectedDocumentId: string | null
  inspector: MatterInspectorView
  filesPage: {
    offset: number
    limit: number
  }
  timelinePage: { offset: number; limit: number; filters: string[] }
  relationshipReview: {
    itemId: string
    requestedRevision: number
    returnTo: string
  } | null
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const INSPECTOR_VIEWS = new Set<MatterInspectorView>(['overview', 'relationships', 'notes'])
const TIMELINE_VIEWS = new Set<MatterTimelineView>(['graph', 'chronology'])

export function shouldRequestMatterTimelineGraph(desktopCapable: boolean, alreadyRequested: boolean) {
  return desktopCapable && !alreadyRequested
}

export function matterTimelineGraphRequestKey(
  matterId: string,
  sourceRevision: string | null,
  filters: readonly string[],
  relationshipRevision?: string,
) {
  return JSON.stringify([matterId, sourceRevision, filters, relationshipRevision ?? null])
}

function scalar(value: string | string[] | undefined) {
  return typeof value === 'string' ? value : undefined
}

export function isMatterSectionId(value: string | undefined): value is MatterSectionId {
  return MATTER_SECTION_IDS.some((section) => section === value)
}

export function parseMatterWorkspaceRoute(
  query: MatterWorkspaceSearchParams = {},
): MatterWorkspaceRouteState {
  const requestedSection = scalar(query.section)
  const section = isMatterSectionId(requestedSection) ? requestedSection : 'timeline'
  const requestedTimelineView = section === 'timeline' ? scalar(query.view) : undefined
  const selectionRequested = query.document !== undefined && (section === 'timeline' || section === 'files')
  const document = selectionRequested ? scalar(query.document) : undefined
  const inspectorValue = selectionRequested ? scalar(query.inspector) : undefined
  const reviewItem = section === 'timeline' ? scalar(query.reviewItem) : undefined
  const reviewRevision = section === 'timeline' ? scalar(query.reviewRevision) : undefined
  const requestedRevision = reviewRevision && /^[1-9]\d{0,8}$/.test(reviewRevision)
    ? Number(reviewRevision)
    : null
  const requestedReturn = section === 'timeline' ? scalar(query.returnTo) : undefined
  const returnTo = (requestedReturn === '/review' || requestedReturn?.startsWith('/review?')) && requestedReturn.length <= 1_000
    ? requestedReturn
    : '/review'

  return {
    section,
    timelineView: requestedTimelineView && TIMELINE_VIEWS.has(requestedTimelineView as MatterTimelineView)
      ? requestedTimelineView as MatterTimelineView
      : 'graph',
    selectionRequested,
    selectedDocumentId: document && UUID_PATTERN.test(document) ? document : null,
    inspector: inspectorValue && INSPECTOR_VIEWS.has(inspectorValue as MatterInspectorView)
      ? inspectorValue as MatterInspectorView
      : 'overview',
    filesPage: normalizeMatterFilesPage({
      offset: scalar(query.filesOffset),
      limit: scalar(query.filesLimit),
    }),
    timelinePage: normalizeMatterTimelinePage({
      offset: scalar(query.timelineOffset),
      limit: scalar(query.timelineLimit),
      filters: Array.isArray(query.filter) ? query.filter : typeof query.filter === 'string' ? [query.filter] : [],
    }),
    relationshipReview: reviewItem && UUID_PATTERN.test(reviewItem) && requestedRevision
      ? { itemId: reviewItem, requestedRevision, returnTo }
      : null,
  }
}

export function buildMatterTimelineViewHref(
  matterId: string,
  currentEntries: Iterable<readonly [string, string]>,
  view: MatterTimelineView,
) {
  const search = new URLSearchParams()
  for (const [key, value] of currentEntries) {
    if (key !== 'view') search.append(key, value)
  }
  search.set('section', 'timeline')
  search.set('view', view)
  return `/matters/${encodeURIComponent(matterId)}?${search.toString()}`
}

export function buildMatterRelationshipSelectionHref(
  matterId: string,
  currentEntries: Iterable<readonly [string, string]>,
  canonicalSourceDocumentId: string,
) {
  const selected = new URL(buildMatterDocumentSelectionHref(
    matterId,
    currentEntries,
    canonicalSourceDocumentId,
  ), 'https://casechain.invalid')
  selected.searchParams.set('inspector', 'relationships')
  return `${selected.pathname}${selected.search}`
}

export function buildMatterTimelinePageHref(
  matterId: string,
  currentEntries: Iterable<readonly [string, string]>,
  page: { offset: number; limit: number },
) {
  const normalized = normalizeMatterTimelinePage(page)
  const search = new URLSearchParams()
  for (const [key, value] of currentEntries) {
    if (key !== 'timelineOffset' && key !== 'timelineLimit') search.append(key, value)
  }
  search.set('section', 'timeline')
  if (normalized.offset > 0) search.set('timelineOffset', String(normalized.offset))
  if (normalized.limit !== MATTER_TIMELINE_DEFAULT_LIMIT) search.set('timelineLimit', String(normalized.limit))
  return `/matters/${encodeURIComponent(matterId)}?${search.toString()}`
}

export function buildMatterTimelineFiltersHref(
  matterId: string,
  currentEntries: Iterable<readonly [string, string]>,
  filters: readonly string[],
) {
  const normalized = normalizeMatterTimelinePage({ filters })
  const search = new URLSearchParams()
  for (const [key, value] of currentEntries) {
    if (key !== 'filter' && key !== 'timelineOffset') search.append(key, value)
  }
  search.set('section', 'timeline')
  normalized.filters.forEach((filter) => search.append('filter', filter))
  return `/matters/${encodeURIComponent(matterId)}?${search.toString()}`
}

export function searchParamEntries(query: MatterWorkspaceSearchParams) {
  const entries: Array<[string, string]> = []
  for (const [key, value] of Object.entries(query)) {
    if (Array.isArray(value)) value.forEach((entry) => entries.push([key, entry]))
    else if (value !== undefined) entries.push([key, value])
  }
  return entries
}

export function buildMatterSectionHref(
  matterId: string,
  currentEntries: Iterable<readonly [string, string]>,
  targetSection: MatterSectionId,
) {
  const search = new URLSearchParams()
  const sectionValues: string[] = []
  for (const [key, value] of currentEntries) {
    search.append(key, value)
    if (key === 'section') sectionValues.push(value)
  }

  const currentSectionValue = sectionValues.length === 1 ? sectionValues[0] : undefined
  const currentSection = isMatterSectionId(currentSectionValue) ? currentSectionValue : 'timeline'
  search.set('section', targetSection)

  if (currentSection !== targetSection || (targetSection !== 'timeline' && targetSection !== 'files')) {
    search.delete('document')
    search.delete('inspector')
  }
  if (targetSection !== 'timeline') search.delete('view')
  if (targetSection !== 'timeline') {
    search.delete('reviewItem')
    search.delete('reviewRevision')
    search.delete('returnTo')
  }
  if (currentSection !== targetSection || targetSection !== 'files') {
    search.delete('filesOffset')
    search.delete('filesLimit')
  }

  return `/matters/${encodeURIComponent(matterId)}?${search.toString()}`
}

export function buildMatterFilesPageHref(
  matterId: string,
  currentEntries: Iterable<readonly [string, string]>,
  page: { offset: number; limit: number },
) {
  const normalized = normalizeMatterFilesPage(page)
  const search = new URLSearchParams()
  for (const [key, value] of currentEntries) {
    if (key !== 'filesOffset' && key !== 'filesLimit') search.append(key, value)
  }
  search.set('section', 'files')
  if (normalized.offset > 0) search.set('filesOffset', String(normalized.offset))
  if (normalized.limit !== MATTER_FILES_DEFAULT_LIMIT) search.set('filesLimit', String(normalized.limit))
  return `/matters/${encodeURIComponent(matterId)}?${search.toString()}`
}

export function buildMatterInspectorHref(
  matterId: string,
  currentEntries: Iterable<readonly [string, string]>,
  inspector: MatterInspectorView,
) {
  const search = new URLSearchParams()
  for (const [key, value] of currentEntries) search.append(key, value)
  search.set('inspector', inspector)
  return `/matters/${encodeURIComponent(matterId)}?${search.toString()}`
}

export function buildMatterDocumentSelectionHref(
  matterId: string,
  currentEntries: Iterable<readonly [string, string]>,
  documentId: string | null,
) {
  const search = new URLSearchParams()
  for (const [key, value] of currentEntries) search.append(key, value)
  if (documentId) search.set('document', documentId)
  else {
    search.delete('document')
    search.delete('inspector')
  }
  const suffix = search.toString()
  return `/matters/${encodeURIComponent(matterId)}${suffix ? `?${suffix}` : ''}`
}

export type SectionLoaderMap<Result> = Record<MatterSectionId, () => Promise<Result>>

/** A small injectable dispatcher keeps lazy-loading behavior directly testable. */
export function loadOnlyActiveMatterSection<Result>(
  section: MatterSectionId,
  loaders: SectionLoaderMap<Result>,
) {
  return loaders[section]()
}
