import { schedules, task } from '@trigger.dev/sdk'
import { createSupabaseOutboxTransport } from '@/lib/outbox/supabase-transport'
import { dispatchLeasedEvents, type DocumentLifecycleEnvelope } from '@/lib/outbox/dispatcher'

export const documentLifecycleEvent = task({
  id: 'document-lifecycle-event',
  retry: { maxAttempts: 1 },
  run: async (payload: Omit<DocumentLifecycleEnvelope, 'leaseToken'>) => ({
    // Acceptance here means Trigger.dev accepted a durable routing envelope.
    // Document processing remains a separate, later downstream concern.
    accepted: true,
    eventId: payload.eventId,
    eventKind: payload.eventKind,
  }),
})

export const dispatchDocumentOutbox = schedules.task({
  id: 'dispatch-document-outbox',
  cron: { pattern: '* * * * *', timezone: 'UTC' },
  run: async () => dispatchLeasedEvents(createSupabaseOutboxTransport(), {
    trigger: (envelope, options) => documentLifecycleEvent.trigger(envelope, options),
  }),
})
