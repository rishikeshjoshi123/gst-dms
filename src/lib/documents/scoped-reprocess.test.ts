import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import {
  isScopedSearchIndexClaim,
  runScopedSearchIndexReprocessWorker,
  type ScopedReprocessRpcClient,
} from './scoped-reprocess'

const claim = {
  code: 'claimed' as const,
  org_id: '20000000-0000-4000-8000-000000000001',
  processing_run_id: '30000000-0000-4000-8000-000000000001',
  document_id: '40000000-0000-4000-8000-000000000001',
  document_version_id: '50000000-0000-4000-8000-000000000001',
  lease_token: '60000000-0000-4000-8000-000000000001',
}

function workerClient(calls: Array<{ name: string; args: Record<string, unknown> }>, input = {
  code: 'ready', doc_type: 'SCN', reference_number: 'SCN/1', summary: 'Synthetic summary.', financial_year: '2024-25', issued_by: 'Authority',
}): ScopedReprocessRpcClient {
  return {
    rpc: async (name, args) => {
      calls.push({ name, args })
      if (name === 'get_document_search_index_reprocess_input') return { data: [input], error: null }
      if (name === 'finish_document_search_index_reprocess_work') return { data: [{ code: args.p_outcome }], error: null }
      return { data: [], error: { message: 'unexpected rpc' } }
    },
  }
}

test('accepts only an identifier-only search-index lease claim', () => {
  assert.equal(isScopedSearchIndexClaim(claim), true)
  assert.equal(isScopedSearchIndexClaim({ ...claim, lease_token: 'not-a-uuid' }), false)
  assert.equal(isScopedSearchIndexClaim({ ...claim, object_key: 'secret.pdf' }), false)
})

test('loads only a leased typed summary and completes the index through the fenced RPC', async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const outcome = await runScopedSearchIndexReprocessWorker(workerClient(calls), claim, async () => ({
    embedding: Array.from({ length: 768 }, () => 0.1),
    inputTokens: 7,
    truncated: false,
    model: 'gemini-embedding-001',
    version: 'gemini-embedding-001-768-v1',
    taskType: 'RETRIEVAL_DOCUMENT',
  }))

  assert.deepEqual(outcome, { outcome: 'indexed' })
  assert.deepEqual(calls.map((call) => call.name), [
    'get_document_search_index_reprocess_input',
    'finish_document_search_index_reprocess_work',
  ])
  assert.deepEqual(calls[0].args, {
    p_processing_run_id: claim.processing_run_id,
    p_lease_token: claim.lease_token,
  })
  assert.equal(calls[1].args.p_outcome, 'indexed')
  assert.match(String(calls[1].args.p_embedding), /^\[(?:0\.1,){767}0\.1\]$/)
})

test('does not retry malformed or truncated embedding output and records only a safe failure', async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const outcome = await runScopedSearchIndexReprocessWorker(workerClient(calls), claim, async () => ({
    embedding: Array.from({ length: 768 }, () => 0.1),
    inputTokens: 7,
    truncated: true,
    model: 'gemini-embedding-001',
    version: 'gemini-embedding-001-768-v1',
    taskType: 'RETRIEVAL_DOCUMENT',
  }))

  assert.deepEqual(outcome, { outcome: 'failed' })
  assert.equal(calls.at(-1)?.args.p_outcome, 'failed')
  assert.equal('p_embedding' in (calls.at(-1)?.args ?? {}), false)
})

test('rejects missing provider token usage and a mismatched configured model without a provider retry', async () => {
  for (const embedding of [
    { inputTokens: undefined as unknown as number, model: 'gemini-embedding-001' },
    { inputTokens: 7, model: 'unapproved-model' },
  ]) {
    const calls: Array<{ name: string; args: Record<string, unknown> }> = []
    const outcome = await runScopedSearchIndexReprocessWorker(workerClient(calls), claim, async () => ({
      embedding: Array.from({ length: 768 }, () => 0.1),
      truncated: false,
      version: 'gemini-embedding-001-768-v1',
      taskType: 'RETRIEVAL_DOCUMENT',
      ...embedding,
    }))
    assert.deepEqual(outcome, { outcome: 'failed' })
    assert.equal(calls.at(-1)?.args.p_outcome, 'failed')
  }
})

test('does not put source content, paths, or embeddings in scoped worker task output', () => {
  const source = readFileSync(new URL('./scoped-reprocess.ts', import.meta.url), 'utf8')

  assert.doesNotMatch(source, /(object_key|storagePath|raw_metadata|signed_url)/)
  assert.match(source, /Promise<\{ outcome: ScopedSearchIndexWorkerOutcome \}>/)
})
