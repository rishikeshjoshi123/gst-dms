import {
  isTrashOperationEffectEventKind,
  isTrashRestoreEventKind,
  type DocumentLifecycleEnvelope,
  type TrashRestoreEventKind,
} from '@/lib/outbox/dispatcher'

type RestoreEffectRpcClient = {
  rpc(name: string, args: Record<string, unknown>): Promise<{
    data: unknown
    error: { message: string } | null
  }>
}

type RestoreEffectResult = {
  code?: unknown
  outcome_code?: unknown
  affected_count?: unknown
}

const routeByEvent: Record<TrashRestoreEventKind, string> = {
  'trash.operation_restored.v1': 'trash-restore-reconciliation',
  'trash.search_reindex_requested.v1': 'trash-restore-search',
  'trash.schedule_reevaluation_requested.v1': 'trash-restore-schedule',
}

const operationCreatedRoute = 'trash-operation-created'

function firstResult(value: unknown): RestoreEffectResult | null {
  if (!Array.isArray(value) || !value[0] || typeof value[0] !== 'object') return null
  return value[0] as RestoreEffectResult
}

/**
 * Complete one leased Restore effect through the private database authority.
 * The RPC revalidates tenant, immutable operation payload, lifecycle state,
 * and delivery lease before it records an idempotent handled result.
 */
export async function runTrashRestoreEffect(
  client: RestoreEffectRpcClient,
  envelope: DocumentLifecycleEnvelope,
) {
  if (!isTrashRestoreEventKind(envelope.eventKind)) {
    throw new Error('Unsupported Restore effect event')
  }

  const result = await client.rpc('handle_trash_restore_effect', {
    p_event_id: envelope.eventId,
    p_expected_org_id: envelope.orgId,
    p_delivery_lease_token: envelope.leaseToken,
    p_expected_event_kind: envelope.eventKind,
  })
  if (result.error) throw new Error('Restore effect authority unavailable')

  const handled = firstResult(result.data)
  if (!handled || (handled.code !== 'handled' && handled.code !== 'already_handled')
    || typeof handled.outcome_code !== 'string'
    || typeof handled.affected_count !== 'number'
    || !Number.isInteger(handled.affected_count)
    || handled.affected_count < 0) {
    throw new Error('Restore effect was not safely handled')
  }

  return {
    accepted: true as const,
    routed: routeByEvent[envelope.eventKind],
    outcome: handled.outcome_code,
    affectedCount: handled.affected_count,
  }
}

/**
 * Complete the creation-time semantic-search invalidation before the outbox
 * acknowledgement. This is deliberately separate from Restore: a creation
 * event must never gain Restore's state assumptions.
 */
export async function runTrashOperationCreatedEffect(
  client: RestoreEffectRpcClient,
  envelope: DocumentLifecycleEnvelope,
) {
  if (!isTrashOperationEffectEventKind(envelope.eventKind) || envelope.eventKind !== 'trash.operation_created.v1') {
    throw new Error('Unsupported Trash creation effect event')
  }
  const result = await client.rpc('handle_trash_operation_created_effect', {
    p_event_id: envelope.eventId,
    p_expected_org_id: envelope.orgId,
    p_delivery_lease_token: envelope.leaseToken,
    p_expected_event_kind: envelope.eventKind,
  })
  if (result.error) throw new Error('Trash creation effect authority unavailable')

  const handled = firstResult(result.data)
  if (!handled || (handled.code !== 'handled' && handled.code !== 'already_handled')
    || typeof handled.outcome_code !== 'string'
    || typeof handled.affected_count !== 'number'
    || !Number.isInteger(handled.affected_count)
    || handled.affected_count < 0) {
    throw new Error('Trash creation effect was not safely handled')
  }
  return {
    accepted: true as const,
    routed: operationCreatedRoute,
    outcome: handled.outcome_code,
    affectedCount: handled.affected_count,
  }
}
