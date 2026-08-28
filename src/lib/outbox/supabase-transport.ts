import { createServiceClient } from '@/lib/supabase/server'
import type { LeasedOutboxEvent, OutboxTransport, SafeDispatchErrorCode } from './dispatcher'

type RpcClient = {
  rpc(name: string, args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>
}

export function createSupabaseOutboxTransport(): OutboxTransport {
  const client = createServiceClient() as unknown as RpcClient

  return {
    async lease(limit, leaseSeconds) {
      const { data, error } = await client.rpc('lease_document_outbox_events', {
        p_limit: limit,
        p_lease_seconds: leaseSeconds,
      })
      if (error) throw new Error('Could not lease document outbox events.')
      return ((data ?? []) as Array<Record<string, unknown>>).map((event) => ({
        eventId: String(event.event_id),
        orgId: String(event.org_id),
        eventKind: String(event.event_kind),
        aggregateType: String(event.aggregate_type),
        aggregateId: String(event.aggregate_id),
        payload: (event.payload ?? {}) as Record<string, unknown>,
        idempotencyKey: String(event.idempotency_key),
        leaseToken: String(event.lease_token),
        attemptNumber: Number(event.attempt_number),
      })) satisfies LeasedOutboxEvent[]
    },
    async ack(eventId, leaseToken, triggerRunId) {
      const { data, error } = await client.rpc('ack_document_outbox_event', {
        p_event_id: eventId,
        p_lease_token: leaseToken,
        p_trigger_run_id: triggerRunId,
      })
      if (error) throw new Error('Could not acknowledge document outbox delivery.')
      return { code: String((data as Array<{ code?: string }> | null)?.[0]?.code ?? 'not_available') }
    },
    async fail(eventId, leaseToken, safeErrorCode) {
      const { data, error } = await client.rpc('fail_document_outbox_event', {
        p_event_id: eventId,
        p_lease_token: leaseToken,
        p_safe_error_code: safeErrorCode,
      })
      if (error) throw new Error('Could not record document outbox delivery failure.')
      return { code: String((data as Array<{ code?: string }> | null)?.[0]?.code ?? 'not_available') }
    },
  }
}
