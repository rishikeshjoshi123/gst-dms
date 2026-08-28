'use server'

export const reprocessScopes = ['extract', 'ocr', 'relationships', 'search_index', 'full'] as const
export type ReprocessScope = typeof reprocessScopes[number]

export function isReprocessScope(scope: unknown): scope is ReprocessScope {
  return typeof scope === 'string' && (reprocessScopes as readonly string[]).includes(scope)
}

export async function reprocessDocument(
  documentId: string,
  scope: ReprocessScope,
) {
  if (!documentId || !isReprocessScope(scope)) {
    return { error: 'Choose one supported reprocessing scope.' }
  }

  // The command exists in the database, but is deliberately not exposed until
  // the dedicated scoped worker is deployed. A durable event without that
  // worker would create an indefinite queued state and mislead the user.
  return { error: 'Scoped reprocessing is unavailable until its dedicated worker is deployed.' }
}
