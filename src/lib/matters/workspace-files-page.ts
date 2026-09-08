export const MATTER_FILES_DEFAULT_LIMIT = 50
export const MATTER_FILES_MAX_LIMIT = 100
export const MATTER_FILES_MAX_OFFSET = 1_000_000

export type MatterFilesPageRequest = {
  offset?: number | string
  limit?: number | string
}

export type NormalizedMatterFilesPage = {
  offset: number
  limit: number
}

const NON_NEGATIVE_INTEGER = /^\d+$/
const POSITIVE_INTEGER = /^[1-9]\d*$/

function boundedInteger(
  value: number | string | undefined,
  fallback: number,
  maximum: number,
  pattern: RegExp,
) {
  if (value === undefined) return fallback
  if (typeof value === 'string' && !pattern.test(value)) return fallback
  const parsed = typeof value === 'number' ? value : Number(value)
  if (!Number.isSafeInteger(parsed) || parsed < 0) return fallback
  return Math.min(parsed, maximum)
}

/** Caller-controlled ranges are strict, finite, and capped before reaching PostgREST. */
export function normalizeMatterFilesPage(
  request: MatterFilesPageRequest = {},
): NormalizedMatterFilesPage {
  return {
    offset: boundedInteger(request.offset, 0, MATTER_FILES_MAX_OFFSET, NON_NEGATIVE_INTEGER),
    limit: boundedInteger(
      request.limit,
      MATTER_FILES_DEFAULT_LIMIT,
      MATTER_FILES_MAX_LIMIT,
      POSITIVE_INTEGER,
    ) || MATTER_FILES_DEFAULT_LIMIT,
  }
}

/** Move an obsolete offset to the last non-empty page after boundary deletes. */
export function clampMatterFilesOffset(offset: number, limit: number, total: number) {
  if (total <= 0) return 0
  if (offset < total) return offset
  return Math.floor((total - 1) / limit) * limit
}

export function matterFilesVisibleRange(page: {
  items: readonly unknown[]
  total: number
  offset: number
}) {
  if (page.total <= 0 || page.items.length === 0) return { start: 0, end: 0 }
  return {
    start: page.offset + 1,
    end: Math.min(page.offset + page.items.length, page.total),
  }
}

export function paginateMatterFiles<T>(
  rows: readonly T[],
  request: MatterFilesPageRequest = {},
) {
  const normalized = normalizeMatterFilesPage(request)
  const offset = clampMatterFilesOffset(normalized.offset, normalized.limit, rows.length)
  return {
    items: rows.slice(offset, offset + normalized.limit),
    total: rows.length,
    offset,
    limit: normalized.limit,
  }
}

type SupportingFileFenceCandidate = {
  id: string
  org_id: string
  matter_id: string
  document_class: string | null
  record_state: string
  deleted_at: string | null
}

/** Defense-in-depth mirror of the active supporting-file database fences. */
export function isActiveSupportingFileCandidate(
  row: SupportingFileFenceCandidate,
  scope: { orgId: string; matterId: string; selectedId?: string },
) {
  return row.org_id === scope.orgId
    && row.matter_id === scope.matterId
    && row.document_class === 'supporting'
    && row.record_state === 'active'
    && row.deleted_at === null
    && (scope.selectedId === undefined || row.id === scope.selectedId)
}

export function compareSupportingFilesNewestFirst(
  left: { id: string; created_at: string },
  right: { id: string; created_at: string },
) {
  const byCreatedAt = right.created_at.localeCompare(left.created_at)
  return byCreatedAt || right.id.localeCompare(left.id)
}
