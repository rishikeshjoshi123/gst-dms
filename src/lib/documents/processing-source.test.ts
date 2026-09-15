import assert from 'node:assert/strict'
import test from 'node:test'
import { createHash } from 'node:crypto'
import { loadCurrentProcessingSource, matchesProcessingSource, processingSourceFailureOutcome, runClaimedModelWithFence, runWithCurrentProcessingSource } from './processing-source'

const bytes = new TextEncoder().encode('%PDF-1.4\nlocal fixture')
const sha256 = createHash('sha256').update(bytes).digest('hex')
const ready = { code: 'ready', document_version_id: 'version', bucket_id: 'documents', object_key: 'private/fixture.pdf', expected_sha256: sha256, expected_bytes: bytes.length }

function client(grants: Array<typeof ready | { code: string }>, download: { data: Blob | null; error: unknown } = { data: new Blob([bytes]), error: null }) {
  const calls: Array<{ name: string; args: unknown }> = []
  let index = 0
  return {
    calls,
    rpc: async (name: string, args: unknown) => {
      calls.push({ name, args })
      return { data: [grants[index++] ?? { code: 'stale_lease' }], error: null }
    },
    storage: { from: (bucket: string) => ({ download: async (path: string) => {
      calls.push({ name: `download:${bucket}`, args: path })
      return download
    } }) },
  }
}

test('only leased RPC authority supplies a locator; stale or Trash never downloads', async () => {
  for (const code of ['stale_lease', 'source_unavailable']) {
    const mock = client([{ code }])
    const result = await loadCurrentProcessingSource(mock as never, 'run', 'lease')
    assert.equal(result.code, code)
    assert.equal(mock.calls.length, 1)
    assert.deepEqual(mock.calls[0]?.args, { p_processing_run_id: 'run', p_lease_token: 'lease' })
  }
})

test('checks downloaded byte size and authoritative SHA-256 before provenance or provider work', async () => {
  const good = client([ready, ready])
  assert.equal((await loadCurrentProcessingSource(good as never, 'run', 'lease')).code, 'ready')
  assert.equal(good.calls.length, 3)
  const mismatch = client([ready], { data: new Blob(['different bytes']), error: null })
  assert.equal((await loadCurrentProcessingSource(mismatch as never, 'run', 'lease')).code, 'source_mismatch')
  assert.equal(mismatch.calls.length, 2)
})

test('re-grant rejects a version or Trash change after initial grant and download', async () => {
  const trash = client([ready, { code: 'source_unavailable' }])
  assert.equal((await loadCurrentProcessingSource(trash as never, 'run', 'lease')).code, 'source_unavailable')
  const changed = client([ready, { ...ready, expected_sha256: 'b'.repeat(64) }])
  assert.equal((await loadCurrentProcessingSource(changed as never, 'run', 'lease')).code, 'source_mismatch')
  const source = { versionId: ready.document_version_id, bucketId: ready.bucket_id, objectKey: ready.object_key, sha256, bytes: Buffer.from(bytes) }
  assert.equal(matchesProcessingSource(ready, source), true)
  assert.equal(matchesProcessingSource({ ...ready, object_key: 'forged/private.pdf' }, source), false)
  assert.equal(matchesProcessingSource({ ...ready, document_version_id: 'forged-version' }, source), false)
  assert.equal(matchesProcessingSource({ ...ready, code: 'stale_lease' }, source), false)
})

test('only explicit missing Storage response is terminal; transient errors are sanitized and retryable', async () => {
  const missing = client([ready], { data: null, error: { status: 404, message: 'secret private path' } })
  assert.equal((await loadCurrentProcessingSource(missing as never, 'run', 'lease')).code, 'storage_missing')
  const transient = client([ready], { data: null, error: { status: 503, message: 'secret private path' } })
  await assert.rejects(loadCurrentProcessingSource(transient as never, 'run', 'lease'), /Document storage temporarily unavailable/)
})

test('worker paid-stage seam invokes no provider when Trash or lease changes before model', async () => {
  const source = { versionId: ready.document_version_id, bucketId: ready.bucket_id, objectKey: ready.object_key, sha256, bytes: Buffer.from(bytes) }
  let providerCalls = 0
  const invokeModel = async () => { providerCalls += 1; return { kind: 'mocked' } }
  const trash = client([{ code: 'source_unavailable' }])
  assert.equal((await runWithCurrentProcessingSource(trash as never, 'run', 'lease', source, invokeModel)).code, 'no_work')
  const stale = client([{ code: 'stale_lease' }])
  assert.equal((await runWithCurrentProcessingSource(stale as never, 'run', 'lease', source, invokeModel)).code, 'no_work')
  assert.equal(providerCalls, 0)
  const live = client([ready])
  assert.equal((await runWithCurrentProcessingSource(live as never, 'run', 'lease', source, invokeModel)).code, 'ready')
  assert.equal(providerCalls, 1)
})

test('pre-provenance source failures cannot claim unsupported Review completion', () => {
  assert.equal(processingSourceFailureOutcome('stale_lease'), 'no_work')
  assert.equal(processingSourceFailureOutcome('source_unavailable'), 'no_work')
  assert.equal(processingSourceFailureOutcome('storage_missing'), 'failed')
  assert.equal(processingSourceFailureOutcome('source_mismatch'), 'failed')
})

test('claimed AI attempt revoked after begin is cancelled without a model call', async () => {
  const source = { versionId: ready.document_version_id, bucketId: ready.bucket_id, objectKey: ready.object_key, sha256, bytes: Buffer.from(bytes) }
  const lease = { processingRunId: 'run', processingLeaseToken: 'lease', sourceAnalysisRunId: 'source', sourceAnalysisLeaseToken: 'source-lease' }
  for (const markerCode of ['not_called', 'source_unavailable']) {
    const calls: string[] = []
    let providerCalls = 0
    const supabase = { rpc: async (name: string) => {
      calls.push(name)
      if (name === 'grant_current_document_processing_source') return { data: [markerCode === 'not_called' ? { code: 'source_unavailable' } : ready], error: null }
      if (name === 'mark_current_document_processing_ai_provider_call') return { data: [{ code: 'source_unavailable' }], error: null }
      return { data: [{ code: 'cancelled' }], error: null }
    } }
    const result = await runClaimedModelWithFence(supabase as never, lease, source, async () => { providerCalls += 1; return 'mocked' })
    assert.equal(result.code, 'no_work')
    assert.equal(providerCalls, 0)
    assert.equal(calls.at(-1), 'cancel_uncalled_document_processing_ai_extraction')
  }
})

test('possibly called AI attempt is not falsely cancelled or retried', async () => {
  const source = { versionId: ready.document_version_id, bucketId: ready.bucket_id, objectKey: ready.object_key, sha256, bytes: Buffer.from(bytes) }
  const lease = { processingRunId: 'run', processingLeaseToken: 'lease', sourceAnalysisRunId: 'source', sourceAnalysisLeaseToken: 'source-lease' }
  let providerCalls = 0
  const calls: string[] = []
  const supabase = { rpc: async (name: string) => {
    calls.push(name)
    if (name === 'grant_current_document_processing_source') return { data: [ready], error: null }
    if (name === 'mark_current_document_processing_ai_provider_call') return { data: [{ code: 'unsafe_to_call' }], error: null }
    return { data: [{ code: 'unsafe_to_cancel' }], error: null }
  } }
  const result = await runClaimedModelWithFence(supabase as never, lease, source, async () => { providerCalls += 1; return 'mocked' })
  assert.equal(result.code, 'failed')
  assert.equal(providerCalls, 0)
  assert.deepEqual(calls, ['grant_current_document_processing_source', 'mark_current_document_processing_ai_provider_call', 'cancel_uncalled_document_processing_ai_extraction'])
})
