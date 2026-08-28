import type { ValidationOutcome } from './validation'

export type ProcessingOutcome = 'placed' | 'needs_review' | 'failed' | 'no_work'
export function safeProcessingOutcome(value: unknown): ProcessingOutcome {
  if (value === 'placed' || value === 'needs_review') return value
  if (value === 'no_work') return 'no_work'
  return 'failed'
}
export function processingIdempotencyKey(eventId: string, versionId: string) {
  return `document-processing:${eventId}:${versionId}`
}
export async function runValidationWorker(
  claim: { expectedBytes: number; download: () => Promise<Uint8Array | null>; finish: (outcome: ValidationOutcome, pageCount: number | null) => Promise<unknown> },
  validate: (bytes: Uint8Array, expectedBytes: number) => Promise<{ outcome: ValidationOutcome; pageCount: number | null }>,
) {
  // `null` is reserved for a confirmed Storage 404. A transport, timeout, or
  // other storage failure must reject so Trigger retries and reconciliation
  // can safely requeue the durable validation lease without terminalising it.
  const bytes = await claim.download()
  const result = bytes ? await validate(bytes, claim.expectedBytes) : { outcome: 'storage_missing' as const, pageCount: null }
  await claim.finish(result.outcome, result.pageCount)
  return result
}
