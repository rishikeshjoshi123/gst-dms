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

export const MATTER_INSPECTOR_LABELS: Record<MatterInspectorView, string> = {
  overview: 'Overview',
  relationships: 'Relationships',
  notes: 'Notes',
}

export type MatterWorkspaceRouteState = {
  section: MatterSectionId
  selectionRequested: boolean
  selectedDocumentId: string | null
  inspector: MatterInspectorView
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const INSPECTOR_VIEWS = new Set<MatterInspectorView>(['overview', 'relationships', 'notes'])

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
  const selectionRequested = query.document !== undefined && (section === 'timeline' || section === 'files')
  const document = selectionRequested ? scalar(query.document) : undefined
  const inspectorValue = selectionRequested ? scalar(query.inspector) : undefined

  return {
    section,
    selectionRequested,
    selectedDocumentId: document && UUID_PATTERN.test(document) ? document : null,
    inspector: inspectorValue && INSPECTOR_VIEWS.has(inspectorValue as MatterInspectorView)
      ? inspectorValue as MatterInspectorView
      : 'overview',
  }
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
