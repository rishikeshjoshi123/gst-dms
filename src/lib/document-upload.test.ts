import assert from 'node:assert/strict'
import test from 'node:test'
import { observeStoredPdf, retainFailedUploads, uploadIdempotencyKey } from './document-upload'

test('observes the stored PDF bytes rather than browser metadata', async () => {
  const observation = await observeStoredPdf(new Blob(['%PDF-1.7\nbody'], { type: 'text/plain' }))

  assert.deepEqual(observation, {
    ok: true,
    byteSize: 13,
    sha256: '3f972854841afd236b04b5d7435b73216bc5fa6e39a86aff6e492b744086189c',
    detectedMime: 'application/pdf',
  })
})

test('rejects an object that lacks a PDF signature', async () => {
  const observation = await observeStoredPdf(new Blob(['not a PDF'], { type: 'application/pdf' }))

  assert.deepEqual(observation, { ok: false, byteSize: 9 })
})

test('accepts only a caller-supplied UUID as an upload idempotency key', () => {
  const key = 'a12c3456-7890-4abc-8def-1234567890ab'
  assert.equal(uploadIdempotencyKey(key), key)
  assert.equal(uploadIdempotencyKey('not-a-uuid'), null)
  assert.equal(uploadIdempotencyKey(null), null)
})

test('retains the original idempotency key for failed upload retries', () => {
  const failed = { idempotencyKey: 'a12c3456-7890-4abc-8def-1234567890ab', name: 'retry.pdf' }
  const succeeded = { idempotencyKey: 'b12c3456-7890-4abc-8def-1234567890ab', name: 'done.pdf' }

  assert.deepEqual(retainFailedUploads([failed, succeeded], new Set([failed.idempotencyKey])), [failed])
})
