export type DocumentHubQuery = {
  matterId?: string | string[]
  intakeId?: string | string[]
}

/** Build the canonical Document Hub route from its allowlisted URL state. */
export function documentHubPath(query: DocumentHubQuery = {}) {
  const params = new URLSearchParams()

  if (typeof query.matterId === 'string' && query.matterId.length > 0) {
    params.set('matterId', query.matterId)
  }
  if (typeof query.intakeId === 'string' && query.intakeId.length > 0) {
    params.set('intakeId', query.intakeId)
  }

  const search = params.toString()
  return search ? `/documents?${search}` : '/documents'
}
