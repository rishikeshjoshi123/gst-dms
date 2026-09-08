import type { InboxQueueDocument, InboxQueueReadResult } from '@/lib/actions/inbox'

export function reconcileInboxQueue(
  current: readonly InboxQueueDocument[],
  result: InboxQueueReadResult,
) {
  if (!result.ok) {
    return {
      documents: [...current],
      error: `${result.error} Showing the last loaded documents.`,
    }
  }

  return {
    documents: Array.from(new Map(result.documents.map(document => [document.id, document])).values()),
    error: null,
  }
}
