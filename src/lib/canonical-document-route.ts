export type CanonicalDocumentRouteQuery = {
  matterId?: string | string[]
  page?: string | string[]
  returnTo?: string | string[]
  version?: string | string[]
}

export type CanonicalDocumentUrlState = {
  matterId?: string
  page?: number
  returnTo?: string
  versionId?: string
  sourceState: 'omitted' | 'valid' | 'invalid'
}

// Accept the complete canonical UUID spelling without constraining fixtures to
// a particular RFC version or variant. The database remains the authority for
// whether an otherwise well-formed ID is an accessible document version.
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const POSITIVE_SAFE_INTEGER_PATTERN = /^[1-9]\d*$/

function scalar(value: string | string[] | undefined) {
  return typeof value === 'string' ? value : undefined
}

/** Read canonical source state without turning an explicit bad locator into latest. */
export function parseCanonicalDocumentUrlState(
  query: CanonicalDocumentRouteQuery = {},
): CanonicalDocumentUrlState {
  const matterId = scalar(query.matterId)
  const returnTo = scalar(query.returnTo)
  const version = scalar(query.version)
  const page = scalar(query.page)
  const parsedPage = page && POSITIVE_SAFE_INTEGER_PATTERN.test(page) ? Number(page) : undefined

  const sourceWasProvided = query.version !== undefined || query.page !== undefined
  const sourceIsInvalid = sourceWasProvided && (
    query.version === undefined || query.page === undefined
    || !version || !UUID_PATTERN.test(version)
    || !page || !parsedPage || !Number.isSafeInteger(parsedPage)
  )
  const sourceIsValid = sourceWasProvided && !sourceIsInvalid

  return {
    ...(matterId && { matterId }),
    ...(returnTo && { returnTo }),
    ...(sourceIsValid && { versionId: version, page: parsedPage }),
    sourceState: sourceIsInvalid ? 'invalid' : sourceWasProvided ? 'valid' : 'omitted',
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
  if (state.returnTo && state.matterId && safeMatterReturnPath(state.returnTo, state.matterId)) {
    params.set('returnTo', state.returnTo)
  }
  if (state.versionId) params.set('version', state.versionId)
  if (state.page) params.set('page', String(state.page))

  return params.size > 0 ? `${path}?${params.toString()}` : path
}

/** Build return state from the exact Matter URL without trusting a browser-supplied path. */
export function buildMatterReturnPath(
  matterId: string,
  currentEntries: Iterable<readonly [string, string]>,
) {
  const search = new URLSearchParams()
  for (const [key, value] of currentEntries) {
    if (key !== 'returnTo') search.append(key, value)
  }
  const suffix = search.toString()
  const path = `/matters/${encodeURIComponent(matterId)}`
  return suffix ? `${path}?${suffix}` : path
}

/** Accept only a same-matter local return path; never turn it into an open redirect. */
export function safeMatterReturnPath(returnTo: string | undefined, matterId: string) {
  if (!returnTo?.startsWith('/') || returnTo.startsWith('//')) return null
  try {
    const parsed = new URL(returnTo, 'https://casechain.invalid')
    const expectedPath = `/matters/${encodeURIComponent(matterId)}`
    if (parsed.origin !== 'https://casechain.invalid' || parsed.pathname !== expectedPath || parsed.hash) return null
    return `${parsed.pathname}${parsed.search}`
  } catch {
    return null
  }
}

/** Preserve raw legacy version/page state so the canonical parser can reject it. */
export function legacyCanonicalDocumentRedirectPath(
  documentId: string,
  matterId: string,
  query: Pick<CanonicalDocumentRouteQuery, 'version' | 'page'> = {},
) {
  const path = `/documents/${encodeURIComponent(documentId)}`
  const params = new URLSearchParams({ matterId })
  for (const key of ['version', 'page'] as const) {
    const value = query[key]
    if (Array.isArray(value)) value.forEach((entry) => params.append(key, entry))
    else if (value !== undefined) params.append(key, value)
  }
  return `${path}?${params.toString()}`
}
