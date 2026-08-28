import assert from 'node:assert/strict'
import test from 'node:test'
import { dispatchLeasedEvents, type LeasedOutboxEvent, type OutboxTransport } from './dispatcher'

const event = (id: string): LeasedOutboxEvent => ({ eventId: id, orgId: 'org-1', eventKind: 'document.processing_requested.v1', aggregateType: 'document', aggregateId: 'doc-1', payload: { document_id: 'doc-1' }, idempotencyKey: `key-${id}`, leaseToken: `lease-${id}`, attemptNumber: 1 })

test('dispatches an empty lease without gateway calls', async () => {
  const transport: OutboxTransport = { lease: async () => [], ack: async () => ({ code: 'ok' }), fail: async () => ({ code: 'retry_scheduled' }) }
  const result = await dispatchLeasedEvents(transport, { trigger: async () => { throw new Error('not called') } })
  assert.deepEqual(result, [])
})

test('acks accepted gateway deliveries with the leased token and idempotency key', async () => {
  const acknowledgements: string[] = []
  const transport: OutboxTransport = { lease: async () => [event('one')], ack: async (_, token, run) => { acknowledgements.push(`${token}:${run}`); return { code: 'ok' } }, fail: async () => ({ code: 'retry_scheduled' }) }
  let idempotencyKey = ''
  const result = await dispatchLeasedEvents(transport, { trigger: async (_, options) => { idempotencyKey = options.idempotencyKey; return { id: 'run-1' } } })
  assert.deepEqual(result, [{ eventId: 'one', code: 'ok' }]); assert.deepEqual(acknowledgements, ['lease-one:run-1']); assert.equal(idempotencyKey, 'key-one')
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
  await dispatchLeasedEvents(transport, { trigger: async (payload) => { if (payload.eventId === 'one') throw new Error('gateway down'); return { id: 'run-2' } } })
  assert.deepEqual(failed, ['one']); assert.deepEqual(acknowledged, ['two'])
})
