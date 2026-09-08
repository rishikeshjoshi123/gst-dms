export const INBOX_QUEUE_PAGE_SIZE = 50
export const INBOX_QUEUE_MAX_PAGE_SIZE = 100
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export type InboxQueuePageOptions = {
  offset?: number
  limit?: number
  includeId?: string
}

export function normalizeInboxQueuePage(options: InboxQueuePageOptions = {}) {
  const offset = Number.isSafeInteger(options.offset) && (options.offset ?? 0) >= 0
    ? options.offset ?? 0
    : 0
  const requestedLimit = Number.isSafeInteger(options.limit) && (options.limit ?? 0) > 0
    ? options.limit ?? INBOX_QUEUE_PAGE_SIZE
    : INBOX_QUEUE_PAGE_SIZE

  const requestedId = options.includeId?.trim()
  return {
    offset,
    limit: Math.min(requestedLimit, INBOX_QUEUE_MAX_PAGE_SIZE),
    includeId: requestedId && UUID_PATTERN.test(requestedId) ? requestedId : undefined,
  }
}
