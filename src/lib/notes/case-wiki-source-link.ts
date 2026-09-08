import {
  canonicalDocumentPath,
  parseCanonicalDocumentUrlState,
  type CanonicalDocumentRouteQuery,
} from '@/lib/canonical-document-route'

export type CaseWikiSourceLinkPresentation =
  | { kind: 'exact'; href: string }
  | { kind: 'unverified'; href: null }
  | { kind: 'other'; href: string }

const CANONICAL_DOCUMENT_PATH = /^\/documents\/([^/?#\\\s]+)$/
const LEGACY_DOCUMENT_PATH = /^\/matters\/([^/?#\\\s]+)\/documents\/([^/?#\\\s]+)$/

function queryValue(params: URLSearchParams, key: 'version' | 'page') {
  const values = params.getAll(key)
  if (values.length === 0) return undefined
  return values.length === 1 ? values[0] : values
}

function safeRouteSegment(value: string) {
  try {
    const decoded = decodeURIComponent(value)
    if (
      !decoded
      || decoded === '.'
      || decoded === '..'
      || decoded.trim() !== decoded
      || /[%\\/?#\u0000-\u001f\u007f]/.test(decoded)
    ) return null
    return decoded
  } catch {
    return null
  }
}

function looksLikeDocumentPath(path: string) {
  return /^\/documents(?:\/|$)/.test(path)
    || /^\/matters(?:\/.*)?\/documents(?:\/|$)/.test(path)
}

function decodedPath(path: string) {
  try {
    return decodeURIComponent(path)
  } catch {
    return path
  }
}

/**
 * Classify links from readable legacy CaseWiki Markdown without looking up source access.
 * Only strict root-relative document paths participate in the immutable source contract.
 */
export function caseWikiSourceLinkPresentation(
  href: string,
  options: { matterId?: string; readOnly?: boolean } = {},
): CaseWikiSourceLinkPresentation {
  if (!href.startsWith('/') || href.startsWith('//')) return { kind: 'other', href }

  const queryIndex = href.indexOf('?')
  const hashIndex = href.indexOf('#')
  const pathEnd = Math.min(
    queryIndex === -1 ? href.length : queryIndex,
    hashIndex === -1 ? href.length : hashIndex,
  )
  const rawPath = href.slice(0, pathEnd)
  const queryEnd = hashIndex === -1 ? href.length : hashIndex
  const query = queryIndex !== -1 && queryIndex < queryEnd
    ? href.slice(queryIndex + 1, queryEnd)
    : ''

  let documentId: string | null = null
  const canonicalMatch = rawPath.match(CANONICAL_DOCUMENT_PATH)
  const legacyMatch = rawPath.match(LEGACY_DOCUMENT_PATH)
  if (canonicalMatch) {
    documentId = safeRouteSegment(canonicalMatch[1])
  } else if (legacyMatch && safeRouteSegment(legacyMatch[1])) {
    documentId = safeRouteSegment(legacyMatch[2])
  }

  if (!documentId) {
    let normalizedPath = rawPath
    try {
      const parsed = new URL(href, 'https://casechain.invalid')
      if (parsed.origin === 'https://casechain.invalid') normalizedPath = parsed.pathname
    } catch {}

    return looksLikeDocumentPath(rawPath)
      || looksLikeDocumentPath(decodedPath(rawPath))
      || looksLikeDocumentPath(decodedPath(normalizedPath))
      ? { kind: 'unverified', href: null }
      : { kind: 'other', href }
  }

  const params = new URLSearchParams(query)
  const locatorQuery: CanonicalDocumentRouteQuery = {
    version: queryValue(params, 'version'),
    page: queryValue(params, 'page'),
  }
  const locator = parseCanonicalDocumentUrlState(locatorQuery)
  if (locator.sourceState !== 'valid') return { kind: 'unverified', href: null }

  return {
    kind: 'exact',
    href: canonicalDocumentPath(documentId, {
      version: locator.versionId,
      page: String(locator.page),
      ...(options.readOnly && options.matterId ? { matterId: options.matterId } : {}),
    }),
  }
}
