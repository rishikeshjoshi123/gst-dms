import assert from 'node:assert/strict'
import test from 'node:test'
import { processingIdempotencyKey, runValidationWorker, safeProcessingOutcome } from './orchestration'

test('maps terminal child results without raw errors', () => {
  assert.equal(safeProcessingOutcome('placed'), 'placed'); assert.equal(safeProcessingOutcome('needs_review'), 'needs_review')
  assert.equal(safeProcessingOutcome('aborted'), 'failed'); assert.equal(safeProcessingOutcome(new Error('secret path')), 'failed')
})
test('maps only an explicit missing object to storage_missing', async () => {
  let finished = ''
  const result = await runValidationWorker({ expectedBytes: 1, download: async () => null, finish: async (outcome) => { finished = outcome } }, async () => ({ outcome: 'ready', pageCount: 1 }))
  assert.deepEqual(result, { outcome: 'storage_missing', pageCount: null }); assert.equal(finished, 'storage_missing')
})
test('propagates transient storage failures without terminal classification', async () => {
  let finished = false
  await assert.rejects(
    () => runValidationWorker({ expectedBytes: 1, download: async () => { throw new Error('storage unavailable') }, finish: async () => { finished = true } }, async () => ({ outcome: 'ready', pageCount: 1 })),
  )
  assert.equal(finished, false)
})
test('creates deterministic version-scoped idempotency keys', () => {
  assert.equal(processingIdempotencyKey('event', 'version'), 'document-processing:event:version')
})
