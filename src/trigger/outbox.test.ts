import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

test('only document.processing_requested dispatches the provenance producer', () => {
  const source = readFileSync(new URL('./outbox.ts', import.meta.url), 'utf8')
  const processing = source.slice(
    source.indexOf("if (payload.eventKind === 'document.processing_requested.v1')"),
    source.indexOf("if (payload.eventKind === 'document.reprocess_requested.v1')"),
  )
  const reprocess = source.slice(source.indexOf("if (payload.eventKind === 'document.reprocess_requested.v1')"))

  assert.match(processing, /await import\('\.\/jobs'\)/)
  assert.match(processing, /p_delivery_lease_token: payload\.leaseToken/)
  assert.match(processing, /processDocument\.triggerAndWait/)
  assert.match(processing, /processingRunId: String\(claim\.processing_run_id\)/)
  assert.match(processing, /processingLeaseToken: String\(claim\.lease_token\)/)
  const childPayload = processing.slice(processing.indexOf('processDocument.triggerAndWait({'), processing.indexOf('}, { idempotencyKey:'))
  assert.doesNotMatch(childPayload, /object_key|storagePath|sha256|documentVersionId|actor_id|orgId|matterId|docId/)
  assert.match(reprocess, /runScopedSearchIndexReprocessWorker/)
  assert.doesNotMatch(reprocess, /processDocument/)
})
