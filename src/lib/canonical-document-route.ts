export type CanonicalDocumentRouteQuery = {
  matterId?: string | string[]
  page?: string | string[]
  version?: string | string[]
}

export type CanonicalDocumentUrlState = {
  matterId?: string
  page?: number
  versionId?: string
}

// Accept the complete canonical UUID spelling without constraining fixtures to
// a particular RFC version or variant. The database remains the authority for
// whether an otherwise well-formed ID is an accessible document version.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const POSITIVE_SAFE_INTEGER_PATTERN = /^[1-9]\d*$/

function scalar(value: string | string[] | undefined) {
  return typeof value === 'string' ? value : undefined
}

/**
 * Read only the canonical document route's URL state. Repeated or malformed
 * values are intentionally indistinguishable from an omitted value.
 */
export function parseCanonicalDocumentUrlState(
  query: CanonicalDocumentRouteQuery = {},
): CanonicalDocumentUrlState {
  const matterId = scalar(query.matterId)
  const version = scalar(query.version)
  const page = scalar(query.page)
  const parsedPage = page && POSITIVE_SAFE_INTEGER_PATTERN.test(page) ? Number(page) : undefined

  return {
    ...(matterId && { matterId }),
    ...(version && UUID_PATTERN.test(version) && { versionId: version }),
    ...(parsedPage && Number.isSafeInteger(parsedPage) && { page: parsedPage }),
  }
}

/** Build the assigned-document route from its allowlisted URL state. */
export function canonicalDocumentPath(
  documentId: string,
  query: CanonicalDocumentRouteQuery = {},
) {
  const path = `/documents/${encodeURIComponent(documentId)}`
  const state = parseCanonicalDocumentUrlState(query)
  const params = new URLSearchParams()
  if (state.matterId) params.set('matterId', state.matterId)
  if (state.versionId) params.set('version', state.versionId)
  if (state.page) params.set('page', String(state.page))

  return params.size > 0 ? `${path}?${params.toString()}` : path
}
