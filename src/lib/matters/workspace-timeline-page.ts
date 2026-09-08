export const MATTER_TIMELINE_DEFAULT_LIMIT = 50
export const MATTER_TIMELINE_MAX_LIMIT = 100
export const MATTER_TIMELINE_MAX_OFFSET = 1_000_000

export type MatterTimelinePageRequest = { offset?: number | string; limit?: number | string; filters?: readonly string[] }
export type NormalizedMatterTimelinePage = { offset: number; limit: number; filters: string[] }
export type MatterTimelineChronologyItem = {
  id: string
  title: string | null
  documentType: string | null
  referenceNumber: string | null
  effectiveDate: string | null
  direction: 'incoming' | 'outgoing' | null
  classificationState: 'canonical' | 'legacy_compatible'
  contentAvailability: string | null
  attentionState: 'none' | 'processing' | 'review' | 'failed'
  revision: string
}
export type MatterTimelineChronologyPage = {
  outcome: 'ok' | 'unavailable'
  items: MatterTimelineChronologyItem[]
  total: number
  unfilteredTotal: number
  offset: number
  limit: number
  fetchedAt: string
  sourceRevision: string | null
  selected: MatterTimelineChronologyItem | null
}

export type MatterTimelineSnapshotDocument = {
  id: string
  matter_id: string | null
  document_class: string | null
  display_title: string | null
  status: string
  current_version_id: string | null
  content_availability: string
  doc_type: string | null
  reference_number: string | null
  doc_date: string | null
  direction: string | null
  has_any_version: boolean
  created_at: string
}

export type MatterTimelineSnapshotMetadata = {
  state: 'available' | 'unavailable'
  documentVersionId: string | null
  docType: string | null
  referenceNumber: string | null
  documentDate: string | null
  direction: string | null
}

export type MatterTimelineSnapshotMetadataRow = {
  document_id: string
  document_version_id: string
  field_path: string
  value_type: string
  normalized_value: unknown
  resolution: string
}

const FILTER = /^(q:.{1,78}|type:.{1,75}|incoming|outgoing|undated|dated|attention:(processing|review|failed|pdf-not-attached)|from:[0-9]{4}-[0-9]{2}-[0-9]{2}|to:[0-9]{4}-[0-9]{2}-[0-9]{2})$/
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/
const CONTROL = /[\u0000-\u001f\u007f]/
const BOUNDARY_WHITESPACE = /^\s|\s$/u
function validDate(value: string) { const date = new Date(`${value}T00:00:00Z`); return ISO_DATE.test(value) && !Number.isNaN(date.valueOf()) && date.toISOString().slice(0, 10) === value }
export function isMatterTimelineFilter(value: string) {
  if (!FILTER.test(value)) return false
  if (value.startsWith('q:') || value.startsWith('type:')) {
    const payload = value.slice(value.indexOf(':') + 1)
    if (CONTROL.test(payload) || BOUNDARY_WHITESPACE.test(payload)) return false
  }
  return !((value.startsWith('from:') && !validDate(value.slice(5))) || (value.startsWith('to:') && !validDate(value.slice(3))))
}

function integer(value: number | string | undefined, fallback: number, max: number, positive = false) {
  if (value === undefined || (typeof value === 'string' && !/^[0-9]+$/.test(value))) return fallback
  const parsed = Number(value)
  if (!Number.isSafeInteger(parsed) || parsed < (positive ? 1 : 0)) return fallback
  return Math.min(parsed, max)
}

/** Query input is bounded before it reaches the secured chronology RPC. */
export function normalizeMatterTimelinePage(request: MatterTimelinePageRequest = {}): NormalizedMatterTimelinePage {
  const rawFilters = request.filters ?? []
  const filters = rawFilters.filter((value) => typeof value === 'string' && isMatterTimelineFilter(value))
  const singletonKinds = ['q:', 'from:', 'to:', 'type:', 'attention:']
  const invalidSet = rawFilters.length > 12
    || filters.length !== rawFilters.length
    || new Set(filters).size !== filters.length
    || singletonKinds.some((kind) => filters.filter((filter) => filter.startsWith(kind)).length > 1)
    || (filters.includes('incoming') && filters.includes('outgoing'))
    || (filters.includes('dated') && filters.includes('undated'))
  const from = filters.find((filter) => filter.startsWith('from:'))?.slice(5)
  const to = filters.find((filter) => filter.startsWith('to:'))?.slice(3)
  return {
    offset: integer(request.offset, 0, MATTER_TIMELINE_MAX_OFFSET),
    limit: integer(request.limit, MATTER_TIMELINE_DEFAULT_LIMIT, MATTER_TIMELINE_MAX_LIMIT, true),
    filters: invalidSet || (from && to && from > to) ? [] : filters,
  }
}

export function clampMatterTimelineOffset(offset: number, limit: number, total: number) {
  if (total <= 0) return 0
  return offset < total ? offset : Math.floor((total - 1) / limit) * limit
}

export function matterTimelineVisibleRange(page: { items: readonly unknown[]; total: number; offset: number }) {
  return page.total <= 0 || page.items.length === 0 ? { start: 0, end: 0 } : { start: page.offset + 1, end: Math.min(page.offset + page.items.length, page.total) }
}

/** Shape only the four exact-current typed fields that Trash chronology uses. */
export function shapeMatterTimelineSnapshotMetadata(
  documentIds: readonly string[],
  rows: readonly MatterTimelineSnapshotMetadataRow[],
): Record<string, MatterTimelineSnapshotMetadata> {
  const result: Record<string, MatterTimelineSnapshotMetadata> = Object.fromEntries(documentIds.map((id) => [id, {
    state: 'unavailable' as const,
    documentVersionId: null,
    docType: null,
    referenceNumber: null,
    documentDate: null,
    direction: null,
  }]))
  const allowed = new Set(documentIds)
  const winning = new Set(['automatic', 'accepted', 'corrected'])
  const specifications = [
    { fieldPath: 'document.type', property: 'docType', valueTypes: ['code'] },
    { fieldPath: 'document.reference_number', property: 'referenceNumber', valueTypes: ['text', 'code'] },
    { fieldPath: 'document.date', property: 'documentDate', valueTypes: ['date'] },
    { fieldPath: 'document.direction', property: 'direction', valueTypes: ['code'] },
  ] as const

  for (const documentId of documentIds) {
    const documentRows = rows.filter((row) => row.document_id === documentId)
    const versions = new Set(documentRows.map((row) => row.document_version_id))
    if (!allowed.has(documentId) || versions.size !== 1) continue
    const metadata: MatterTimelineSnapshotMetadata = {
      state: 'available',
      documentVersionId: [...versions][0],
      docType: null,
      referenceNumber: null,
      documentDate: null,
      direction: null,
    }
    for (const specification of specifications) {
      const candidates = documentRows.filter((row) => row.field_path === specification.fieldPath && winning.has(row.resolution))
      if (candidates.length !== 1) continue
      const candidate = candidates[0]
      if (!(specification.valueTypes as readonly string[]).includes(candidate.value_type)
        || typeof candidate.normalized_value !== 'string'
        || candidate.normalized_value.length === 0) continue
      if (specification.fieldPath === 'document.date' && !validDate(candidate.normalized_value)) continue
      if (specification.fieldPath === 'document.direction' && candidate.normalized_value !== 'incoming' && candidate.normalized_value !== 'outgoing') continue
      metadata[specification.property] = candidate.normalized_value
    }
    result[documentId] = metadata
  }
  return result
}

function snapshotAttention(status: string): MatterTimelineChronologyItem['attentionState'] {
  if (status === 'failed') return 'failed'
  if (status === 'needs_review') return 'review'
  if (status === 'uploaded' || status === 'processing' || status === 'pending_placement') return 'processing'
  return 'none'
}

function stableSnapshotRevision(parts: readonly string[]) {
  let hash = 2166136261
  for (const character of parts.join('\u001f')) {
    hash ^= character.charCodeAt(0)
    hash = Math.imul(hash, 16777619)
  }
  return `trash-${(hash >>> 0).toString(16).padStart(8, '0')}`
}

function matchesSnapshotFilters(item: MatterTimelineChronologyItem, filters: readonly string[]) {
  return filters.every((filter) => {
    if (filter === 'incoming' || filter === 'outgoing') return item.direction === filter
    if (filter === 'dated') return item.effectiveDate !== null
    if (filter === 'undated') return item.effectiveDate === null
    if (filter === 'attention:pdf-not-attached') return item.contentAvailability === 'metadata_only'
    if (filter.startsWith('attention:')) return item.attentionState === filter.slice(10)
    if (filter.startsWith('q:')) {
      const query = filter.slice(2).toLocaleLowerCase()
      return `${item.title ?? ''} ${item.referenceNumber ?? ''}`.toLocaleLowerCase().includes(query)
    }
    if (filter.startsWith('type:')) return item.documentType?.toLocaleLowerCase() === filter.slice(5).toLocaleLowerCase()
    if (filter.startsWith('from:')) return item.effectiveDate !== null && item.effectiveDate >= filter.slice(5)
    if (filter.startsWith('to:')) return item.effectiveDate !== null && item.effectiveDate <= filter.slice(3)
    return false
  })
}

/**
 * Trash chronology is shaped only from the exact, already-authorised snapshot.
 * It never revives legacy metadata: typed fields require the exact current
 * version's secured inspector projection, while unavailable content stays null.
 */
export function createMatterTimelineSnapshotPage(
  matterId: string,
  documents: readonly MatterTimelineSnapshotDocument[],
  metadataByDocumentId: Readonly<Record<string, MatterTimelineSnapshotMetadata | undefined>>,
  request: MatterTimelinePageRequest = {},
  selectedDocumentId: string | null = null,
): MatterTimelineChronologyPage {
  const normalized = normalizeMatterTimelinePage(request)
  const createdAtByDocumentId = new Map(documents.map((document) => [document.id, document.created_at]))
  const allItems = documents
    .filter((document) => document.matter_id === matterId && (document.document_class === 'proceeding' || document.document_class === null))
    .map((document): MatterTimelineChronologyItem => {
      const metadata = metadataByDocumentId[document.id]
      const exactMetadata = metadata?.state === 'available'
        && document.current_version_id !== null
        && metadata.documentVersionId === document.current_version_id
      const genuineMetadataOnly = document.content_availability === 'metadata_only'
        && document.current_version_id === null
        && !document.has_any_version
      const documentType = exactMetadata ? metadata.docType : genuineMetadataOnly ? document.doc_type : null
      const referenceNumber = exactMetadata ? metadata.referenceNumber : genuineMetadataOnly ? document.reference_number : null
      const candidateDate = exactMetadata ? metadata.documentDate : genuineMetadataOnly ? document.doc_date : null
      const candidateDirection = exactMetadata ? metadata.direction : genuineMetadataOnly ? document.direction : null
      const effectiveDate = candidateDate && validDate(candidateDate) ? candidateDate : null
      const direction = candidateDirection === 'incoming' || candidateDirection === 'outgoing' ? candidateDirection : null
      const values = [
        document.id,
        document.display_title ?? '',
        document.document_class ?? '',
        document.created_at,
        document.current_version_id ?? '',
        document.content_availability,
        document.has_any_version ? 'has-version' : 'zero-versions',
        document.status,
        documentType ?? '',
        referenceNumber ?? '',
        effectiveDate ?? '',
        direction ?? '',
      ]
      return {
        id: document.id,
        title: document.display_title,
        documentType,
        referenceNumber,
        effectiveDate,
        direction,
        classificationState: document.document_class === 'proceeding' ? 'canonical' : 'legacy_compatible',
        contentAvailability: document.content_availability,
        attentionState: snapshotAttention(document.status),
        revision: stableSnapshotRevision(values),
      }
    })
    .sort((left, right) => {
      if (left.effectiveDate === null && right.effectiveDate !== null) return 1
      if (left.effectiveDate !== null && right.effectiveDate === null) return -1
      if (left.effectiveDate !== right.effectiveDate) return (left.effectiveDate ?? '').localeCompare(right.effectiveDate ?? '')
      const leftCreated = createdAtByDocumentId.get(left.id) ?? ''
      const rightCreated = createdAtByDocumentId.get(right.id) ?? ''
      return leftCreated.localeCompare(rightCreated) || left.id.localeCompare(right.id)
    })
  const filtered = allItems.filter((item) => matchesSnapshotFilters(item, normalized.filters))
  const offset = clampMatterTimelineOffset(normalized.offset, normalized.limit, filtered.length)
  const selected = selectedDocumentId ? allItems.find((item) => item.id === selectedDocumentId) ?? null : null
  return {
    outcome: 'ok',
    items: filtered.slice(offset, offset + normalized.limit),
    total: filtered.length,
    unfilteredTotal: allItems.length,
    offset,
    limit: normalized.limit,
    fetchedAt: new Date().toISOString(),
    sourceRevision: stableSnapshotRevision(allItems.map((item) => item.revision)),
    selected,
  }
}
