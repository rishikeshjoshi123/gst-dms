import { after } from 'next/server'

export type DocumentOutboxWakePayload = Readonly<Record<never, never>>

export const documentOutboxWakePayload: DocumentOutboxWakePayload = {}
export const documentOutboxWakeOptions = {
  debounce: {
    key: 'document-outbox-dispatch',
    delay: '5s',
    maxDelay: '30s',
  },
} as const

export type DocumentOutboxWakeTrigger = (
  payload: typeof documentOutboxWakePayload,
  options: typeof documentOutboxWakeOptions,
) => Promise<unknown>

type AfterScheduler = (callback: () => void | Promise<void>) => void
type SafeWakeLogger = (message: string) => void

async function triggerSingletonDocumentOutboxDispatcher(
  payload: typeof documentOutboxWakePayload,
  options: typeof documentOutboxWakeOptions,
) {
  const { documentOutboxDispatcher } = await import('@/trigger/outbox')
  return documentOutboxDispatcher.trigger(payload, options)
}

/**
 * Submit a fixed, content-free wake for the singleton dispatcher. The database
 * already owns the durable event and the one-minute schedule recovers a missed
 * wake, so a gateway failure is intentionally observable but never fatal to
 * the domain write that preceded it.
 */
export async function submitDocumentOutboxWake(
  trigger: DocumentOutboxWakeTrigger = triggerSingletonDocumentOutboxDispatcher,
  log: SafeWakeLogger = console.warn,
) {
  try {
    await trigger(documentOutboxWakePayload, documentOutboxWakeOptions)
    return { accepted: true as const }
  } catch {
    log('Document outbox wake was not accepted; scheduled recovery will drain durable work.')
    return { accepted: false as const }
  }
}

/**
 * Queue a best-effort wake after a successful server-side domain transaction.
 * Callers cannot select a task identifier, attach a payload, or observe a
 * gateway error as a failed document command.
 */
export function scheduleDocumentOutboxWake(
  schedule: AfterScheduler = after,
  trigger: DocumentOutboxWakeTrigger = triggerSingletonDocumentOutboxDispatcher,
  log: SafeWakeLogger = console.warn,
) {
  schedule(async () => {
    await submitDocumentOutboxWake(trigger, log)
  })
}
