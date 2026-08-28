import { createServiceClient } from '@/lib/supabase/server'
import {
  isSafeLeasedOutboxEvent,
  type LeasedOutboxEvent,
  type OutboxTransport,
} from './dispatcher'

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
      const leased: LeasedOutboxEvent[] = []
      for (const row of (data ?? []) as Array<Record<string, unknown>>) {
        const candidate = {
          eventId: row.event_id,
          orgId: row.org_id,
          eventKind: row.event_kind,
          aggregateType: row.aggregate_type,
          aggregateId: row.aggregate_id,
          payload: row.payload,
          idempotencyKey: row.idempotency_key,
          leaseToken: row.lease_token,
          attemptNumber: row.attempt_number,
        }
        if (!isSafeLeasedOutboxEvent(candidate)) {
          if (typeof row.event_id !== 'string' || typeof row.lease_token !== 'string') {
            throw new Error('Outbox lease omitted its delivery fence.')
          }
          const failed = await client.rpc('fail_document_outbox_event', {
            p_event_id: row.event_id,
            p_lease_token: row.lease_token,
            p_safe_error_code: 'dispatch_failed',
          })
          if (failed.error) throw new Error('Could not safely reject an invalid outbox lease.')
          continue
        }
        leased.push(candidate)
      }
      return leased
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
