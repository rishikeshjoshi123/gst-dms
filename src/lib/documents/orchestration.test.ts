import assert from 'node:assert/strict'
import test from 'node:test'
import { processingIdempotencyKey, runValidationWorker, safeProcessingOutcome } from './orchestration'

test('maps terminal child results without raw errors', () => {
  assert.equal(safeProcessingOutcome('placed'), 'placed'); assert.equal(safeProcessingOutcome('needs_review'), 'needs_review')
  assert.equal(safeProcessingOutcome('aborted'), 'failed'); assert.equal(safeProcessingOutcome(new Error('secret path')), 'failed')
})
test('maps a rejecting storage download to storage_missing without leaking its error', async () => {
  let finished = ''
  const result = await runValidationWorker({ expectedBytes: 1, download: async () => { throw new Error('secret/path.pdf') }, finish: async (outcome) => { finished = outcome } }, async () => ({ outcome: 'ready', pageCount: 1 }))
  assert.deepEqual(result, { outcome: 'storage_missing', pageCount: null }); assert.equal(finished, 'storage_missing')
})
test('creates deterministic version-scoped idempotency keys', () => {
  assert.equal(processingIdempotencyKey('event', 'version'), 'document-processing:event:version')
})
