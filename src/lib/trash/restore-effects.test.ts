import assert from 'node:assert/strict'
import test from 'node:test'

import type { DocumentLifecycleEnvelope, TrashRestoreEventKind } from '@/lib/outbox/dispatcher'
import { runTrashRestoreEffect } from './restore-effects'

const kinds: TrashRestoreEventKind[] = [
  'trash.operation_restored.v1',
  'trash.search_reindex_requested.v1',
  'trash.schedule_reevaluation_requested.v1',
]

function envelope(eventKind: TrashRestoreEventKind): DocumentLifecycleEnvelope {
  return {
    eventId: '10000000-0000-0000-0000-000000000001',
    orgId: '20000000-0000-0000-0000-000000000001',
    eventKind,
    aggregateType: 'trash_operation',
    aggregateId: '30000000-0000-0000-0000-000000000001',
    payload: {
      operation_id: '30000000-0000-0000-0000-000000000001',
      root_resource_id: '40000000-0000-0000-0000-000000000001',
      root_resource_type: 'document',
    },
    idempotencyKey: 'trash.restore.test',
    leaseToken: '50000000-0000-0000-0000-000000000001',
  }
}

test('routes and completes every Restore event through the fenced effect RPC', async () => {
  for (const eventKind of kinds) {
    const calls: Array<{ name: string; args: Record<string, unknown> }> = []
    const result = await runTrashRestoreEffect({
      rpc: async (name, args) => {
        calls.push({ name, args })
        return { data: [{ code: 'handled', outcome_code: 'operation_reconciled', affected_count: 2 }], error: null }
      },
    }, envelope(eventKind))
    assert.equal(result.accepted, true)
    assert.match(result.routed, /^trash-restore-/)
    assert.deepEqual(calls, [{
      name: 'handle_trash_restore_effect',
      args: {
        p_event_id: '10000000-0000-0000-0000-000000000001',
        p_expected_org_id: '20000000-0000-0000-0000-000000000001',
        p_delivery_lease_token: '50000000-0000-0000-0000-000000000001',
        p_expected_event_kind: eventKind,
      },
    }])
  }
})

test('rejects unhandled, stale, or unavailable Restore effects', async () => {
  await assert.rejects(runTrashRestoreEffect({
    rpc: async () => ({ data: [{ code: 'state_mismatch', outcome_code: null, affected_count: 0 }], error: null }),
  }, envelope('trash.search_reindex_requested.v1')))
  await assert.rejects(runTrashRestoreEffect({
    rpc: async () => ({ data: null, error: { message: 'private detail' } }),
  }, envelope('trash.schedule_reevaluation_requested.v1')))
})
