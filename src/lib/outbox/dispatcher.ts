export type DocumentLifecycleEnvelope = {
  eventId: string
  orgId: string
  eventKind: string
  aggregateType: string
  aggregateId: string
  payload: Record<string, unknown>
  idempotencyKey: string
  leaseToken: string
}

export type LeasedOutboxEvent = DocumentLifecycleEnvelope & { attemptNumber: number }

export type OutboxTransport = {
  lease(limit: number, leaseSeconds: number): Promise<LeasedOutboxEvent[]>
  ack(eventId: string, leaseToken: string, triggerRunId: string): Promise<{ code: string }>
  fail(eventId: string, leaseToken: string, safeErrorCode: SafeDispatchErrorCode): Promise<{ code: string }>
}

export type SafeDispatchErrorCode =
  | 'gateway_unavailable'
  | 'gateway_timeout'
  | 'gateway_rejected'
  | 'dispatch_failed'

export type TriggerGateway = {
  trigger(envelope: Omit<DocumentLifecycleEnvelope, 'leaseToken'>, options: { idempotencyKey: string }): Promise<{ id: string }>
}

export function safeDispatchErrorCode(_: unknown): SafeDispatchErrorCode {
  // Gateway exceptions can carry arbitrary provider data. The durable ledger
  // receives a stable operational code only; raw errors never cross this boundary.
  return 'gateway_unavailable'
}

export async function dispatchLeasedEvents(
  transport: OutboxTransport,
  gateway: TriggerGateway,
  options: { limit?: number; leaseSeconds?: number } = {},
) {
  const events = await transport.lease(options.limit ?? 25, options.leaseSeconds ?? 120)
  const results: Array<{ eventId: string; code: string }> = []

  for (const event of events) {
    const { leaseToken, attemptNumber: _, ...envelope } = event
    try {
      const run = await gateway.trigger(envelope, { idempotencyKey: event.idempotencyKey })
      const acknowledgement = await transport.ack(event.eventId, leaseToken, run.id)
      results.push({ eventId: event.eventId, code: acknowledgement.code })
    } catch (error) {
      const failure = await transport.fail(event.eventId, leaseToken, safeDispatchErrorCode(error))
      results.push({ eventId: event.eventId, code: failure.code })
    }
  }

  return results
}
