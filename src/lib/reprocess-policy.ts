export const reprocessScopes = ['extract', 'ocr', 'relationships', 'search_index', 'full'] as const
export type ReprocessScope = typeof reprocessScopes[number]

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function isReprocessScope(scope: unknown): scope is ReprocessScope {
  return typeof scope === 'string' && (reprocessScopes as readonly string[]).includes(scope)
}

export function isReprocessIdempotencyKey(value: unknown): value is string {
  return typeof value === 'string' && uuidPattern.test(value)
}

export function isReprocessDocumentId(value: unknown): value is string {
  return typeof value === 'string' && uuidPattern.test(value)
}
