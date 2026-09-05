export type CanonicalDocumentRouteQuery = {
  matterId?: string | string[]
}

/** Build the assigned-document route from its allowlisted URL state. */
export function canonicalDocumentPath(
  documentId: string,
  query: CanonicalDocumentRouteQuery = {},
) {
  const path = `/documents/${encodeURIComponent(documentId)}`
  if (typeof query.matterId !== 'string' || query.matterId.length === 0) return path

  const params = new URLSearchParams({ matterId: query.matterId })
  return `${path}?${params.toString()}`
}
