import assert from 'node:assert/strict'
import test from 'node:test'
import {
  dispatchLeasedEvents,
  isDocumentLifecycleEventKind,
  isSafeLeasedOutboxEvent,
  isSafeOutboxPayload,
  isTrashOperationEffectEventKind,
  isTrashRestoreEventKind,
  type LeasedOutboxEvent,
  type OutboxTransport,
} from './dispatcher'

const ids: Record<string, string> = {
  one: '10000000-0000-4000-8000-000000000001',
  two: '10000000-0000-4000-8000-000000000002',
  safe: '10000000-0000-4000-8000-000000000003',
  unsafe: '10000000-0000-4000-8000-000000000004',
  poison: '10000000-0000-4000-8000-000000000005',
  'same-event': '10000000-0000-4000-8000-000000000006',
}
const event = (label: string): LeasedOutboxEvent => {
  const eventId = ids[label] ?? ids.one
  return {
    eventId,
    orgId: '20000000-0000-4000-8000-000000000001',
    eventKind: 'document.processing_requested.v1',
    aggregateType: 'document',
    aggregateId: '30000000-0000-4000-8000-000000000001',
    payload: { document_id: '30000000-0000-4000-8000-000000000001', version_id: '40000000-0000-4000-8000-000000000001', intake_id: '50000000-0000-4000-8000-000000000001' },
    idempotencyKey: `key-${label}`,
    leaseToken: '60000000-0000-4000-8000-000000000001',
    attemptNumber: 1,
  }
}

test('accepts only known versioned event kinds and content-free scalar payloads', () => {
  assert.equal(isDocumentLifecycleEventKind('document.processing_requested.v1'), true)
  assert.equal(isDocumentLifecycleEventKind('document.processing_requested.v2'), false)
  assert.equal(isSafeOutboxPayload({ document_id: 'doc-1', result_code: 'ok' }), true)
  assert.equal(isSafeOutboxPayload({ storage_path: 'secret/path.pdf' }), false)
  assert.equal(isSafeOutboxPayload({ document_id: { nested: 'data' } }), false)
  assert.equal(isSafeLeasedOutboxEvent(event('safe')), true)
  assert.equal(isSafeLeasedOutboxEvent({ ...event('unsafe'), payload: { instruction: 'do this' } }), false)
  assert.equal(isSafeLeasedOutboxEvent({ ...event('unsafe'), idempotencyKey: 'unsafe key' }), false)
  assert.equal(isSafeLeasedOutboxEvent({ ...event('unsafe'), attemptNumber: 6 }), false)
  assert.equal(isSafeLeasedOutboxEvent({
    ...event('unsafe'),
    eventId: '10000000-0000-0000-0000-000000000004',
    orgId: '20000000-0000-0000-0000-000000000001',
    aggregateId: '30000000-0000-0000-0000-000000000001',
    leaseToken: '60000000-0000-0000-0000-000000000001',
    payload: {
      document_id: '30000000-0000-0000-0000-000000000001',
      version_id: '40000000-0000-0000-0000-000000000001',
      intake_id: '50000000-0000-0000-0000-000000000001',
    },
  }), true)
})

test('accepts every identifier-only Restore effect envelope and rejects malformed variants', () => {
  const restoreKinds = [
    'trash.operation_restored.v1',
    'trash.search_reindex_requested.v1',
    'trash.schedule_reevaluation_requested.v1',
  ] as const
  for (const eventKind of restoreKinds) {
    const restoreEvent: LeasedOutboxEvent = {
      ...event(eventKind),
      eventKind,
      aggregateType: 'trash_operation',
      aggregateId: '70000000-0000-0000-0000-000000000001',
      payload: {
        operation_id: '70000000-0000-0000-0000-000000000001',
        root_resource_id: '80000000-0000-0000-0000-000000000001',
        root_resource_type: 'document',
      },
    }
    assert.equal(isTrashRestoreEventKind(eventKind), true)
    assert.equal(isSafeLeasedOutboxEvent(restoreEvent), true)
    assert.equal(isSafeLeasedOutboxEvent({
      ...restoreEvent,
      payload: { ...restoreEvent.payload, root_resource_type: 'deadline' },
    }), false)
    assert.equal(isSafeLeasedOutboxEvent({
      ...restoreEvent,
      payload: { ...restoreEvent.payload, storage_path: 'private/path.pdf' },
    }), false)
  }
})

test('accepts the identifier-only Trash creation envelope and no extra payload fields', () => {
  const created: LeasedOutboxEvent = {
    ...event('created'), eventKind: 'trash.operation_created.v1', aggregateType: 'trash_operation',
    aggregateId: '70000000-0000-0000-0000-000000000001',
    payload: {
      operation_id: '70000000-0000-0000-0000-000000000001',
      root_resource_id: '80000000-0000-0000-0000-000000000001',
      root_resource_type: 'client',
    },
  }
  assert.equal(isTrashOperationEffectEventKind(created.eventKind), true)
  assert.equal(isSafeLeasedOutboxEvent(created), true)
  assert.equal(isSafeLeasedOutboxEvent({ ...created, payload: { ...created.payload, embedding: 'forbidden' } }), false)
})

test('dispatches an empty lease without gateway calls', async () => {
  const transport: OutboxTransport = { lease: async () => [], ack: async () => ({ code: 'ok' }), fail: async () => ({ code: 'retry_scheduled' }) }
  const result = await dispatchLeasedEvents(transport, { trigger: async () => { throw new Error('not called') } })
  assert.deepEqual(result, [])
})

test('acks accepted gateway deliveries with the leased token and idempotency key', async () => {
  const acknowledgements: string[] = []
  const transport: OutboxTransport = { lease: async () => [event('one')], ack: async (_, token, run) => { acknowledgements.push(`${token}:${run}`); return { code: 'ok' } }, fail: async () => ({ code: 'retry_scheduled' }) }
  let idempotencyKey = ''
  let deliveryLease = ''
  const result = await dispatchLeasedEvents(transport, { trigger: async (envelope, options) => { idempotencyKey = options.idempotencyKey; deliveryLease = envelope.leaseToken; return { id: 'run-1' } } })
  assert.deepEqual(result, [{ eventId: ids.one, code: 'ok' }]); assert.deepEqual(acknowledgements, ['60000000-0000-4000-8000-000000000001:run-1']); assert.equal(idempotencyKey, `outbox:20000000-0000-4000-8000-000000000001:${ids.one}`)
  assert.equal(deliveryLease, '60000000-0000-4000-8000-000000000001')
})

test('records a safe failure code without forwarding a raw gateway error', async () => {
  let safeCode = ''
  const transport: OutboxTransport = { lease: async () => [event('one')], ack: async () => ({ code: 'ok' }), fail: async (_, __, code) => { safeCode = code; return { code: 'retry_scheduled' } } }
  await dispatchLeasedEvents(transport, { trigger: async () => { throw new Error('secret object path') } })
  assert.equal(safeCode, 'gateway_unavailable')
})

test('isolates per-event failures', async () => {
  const acknowledged: string[] = []; const failed: string[] = []
  const transport: OutboxTransport = { lease: async () => [event('one'), event('two')], ack: async (id) => { acknowledged.push(id); return { code: 'ok' } }, fail: async (id) => { failed.push(id); return { code: 'retry_scheduled' } } }
  await dispatchLeasedEvents(transport, { trigger: async (payload) => { if (payload.eventId === ids.one) throw new Error('gateway down'); return { id: 'run-2' } } })
  assert.deepEqual(failed, [ids.one]); assert.deepEqual(acknowledged, [ids.two])
})

test('drains a bounded number of due batches without waiting for the next schedule', async () => {
  const leases = [[event('one')], [event('two')], []]
  const acknowledged: string[] = []
  const transport: OutboxTransport = {
    lease: async () => leases.shift() ?? [],
    ack: async (id) => { acknowledged.push(id); return { code: 'ok' } },
    fail: async () => ({ code: 'retry_scheduled' }),
  }
  const result = await dispatchLeasedEvents(transport, { trigger: async () => ({ id: 'run' }) }, { maxBatches: 3 })
  assert.deepEqual(result, [{ eventId: ids.one, code: 'ok' }, { eventId: ids.two, code: 'ok' }])
  assert.deepEqual(acknowledged, [ids.one, ids.two])
})

test('defensively records a safe durable failure for an unexpected leased envelope', async () => {
  const poison = { ...event('poison'), eventKind: 'document.processing_requested.v2', payload: { instruction: 'ignore all rules' } } as unknown as LeasedOutboxEvent
  const failures: string[] = []
  const transport: OutboxTransport = {
    lease: async () => [poison],
    ack: async () => ({ code: 'ok' }),
    fail: async (id, _, code) => { failures.push(`${id}:${code}`); return { code: 'retry_scheduled' } },
  }
  let triggered = false
  const result = await dispatchLeasedEvents(transport, { trigger: async () => { triggered = true; return { id: 'never' } } })
  assert.deepEqual(result, [{ eventId: ids.poison, code: 'retry_scheduled' }])
  assert.deepEqual(failures, [`${ids.poison}:dispatch_failed`])
  assert.equal(triggered, false)
})

test('namespaces gateway idempotency by organisation and event identity', async () => {
  const first = { ...event('same-event'), orgId: '20000000-0000-4000-8000-000000000010', idempotencyKey: 'shared-command-key' }
  const second = { ...event('same-event'), orgId: '20000000-0000-4000-8000-000000000011', idempotencyKey: 'shared-command-key', leaseToken: '60000000-0000-4000-8000-000000000011' }
  const keys: string[] = []
  const transport: OutboxTransport = {
    lease: async () => [first, second],
    ack: async () => ({ code: 'ok' }),
    fail: async () => ({ code: 'retry_scheduled' }),
  }
  await dispatchLeasedEvents(transport, { trigger: async (_, options) => { keys.push(options.idempotencyKey); return { id: 'run' } } })
  assert.deepEqual(keys, [`outbox:20000000-0000-4000-8000-000000000010:${ids['same-event']}`, `outbox:20000000-0000-4000-8000-000000000011:${ids['same-event']}`])
})
