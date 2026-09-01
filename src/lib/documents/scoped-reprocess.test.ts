import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import {
  hasCurrentSearchIndexEmbedding,
  buildSearchPageChunks,
  isScopedSearchIndexClaim,
  runScopedSearchIndexReprocessWorker,
  serializeSearchIndexEmbedding,
  type ScopedReprocessRpcClient,
} from './scoped-reprocess'
import type { EmbeddingResult } from '@/lib/ai/vertex'

const claim = {
  code: 'claimed' as const,
  org_id: '20000000-0000-4000-8000-000000000001',
  processing_run_id: '30000000-0000-4000-8000-000000000001',
  document_id: '40000000-0000-4000-8000-000000000001',
  document_version_id: '50000000-0000-4000-8000-000000000001',
  lease_token: '60000000-0000-4000-8000-000000000001',
}

type WorkerInput = {
  code: string
  doc_type: string | null
  reference_number: string | null
  summary: string | null
  financial_years: string[] | null
  issued_by: string | null
  projection_fingerprint: string | null
}

function workerClient(calls: Array<{ name: string; args: Record<string, unknown> }>, input: WorkerInput = {
  code: 'ready', doc_type: 'SCN', reference_number: 'SCN/1', summary: 'Synthetic summary.', financial_years: ['2024-25'], issued_by: 'Authority', projection_fingerprint: 'a'.repeat(64),
}): ScopedReprocessRpcClient {
  return {
    rpc: async (name, args) => {
      calls.push({ name, args })
      if (name === 'get_document_search_index_reprocess_input') return { data: [input], error: null }
      if (name === 'get_document_search_page_text_reprocess_input') return { data: [{ code: 'not_indexable', pages: null, existing_content_hashes: null }], error: null }
      if (name === 'write_current_document_search_page_chunks') return { data: [{ code: 'not_indexable', changed_chunk_count: 0 }], error: null }
      if (name === 'finish_document_search_index_reprocess_work') return { data: [{ code: args.p_outcome }], error: null }
      return { data: [], error: { message: 'unexpected rpc' } }
    },
  }
}

function corpusProvider(result: EmbeddingResult, onRequest?: (request: { input: string; purpose: string }) => void) {
  return {
    embed: async (request: { input: string; purpose: 'corpus' | 'query' | 'similarity' }) => {
      onRequest?.(request)
      return result
    },
  }
}

function validCorpusEmbedding(): EmbeddingResult {
  return {
    embedding: Array.from({ length: 768 }, () => 0.1),
    dimensions: 768,
    inputTokens: 7,
    billableUsage: null,
    truncated: false,
    model: 'gemini-embedding-001',
    version: 'gemini-embedding-001-768-v1',
    purpose: 'corpus',
  }
}

test('accepts only an identifier-only search-index lease claim', () => {
  assert.equal(isScopedSearchIndexClaim(claim), true)
  assert.equal(isScopedSearchIndexClaim({ ...claim, lease_token: 'not-a-uuid' }), false)
  assert.equal(isScopedSearchIndexClaim({ ...claim, object_key: 'secret.pdf' }), false)
})

test('uses PostgreSQL-compatible Unicode character locators for page chunks', () => {
  const chunks = buildSearchPageChunks({
    code: 'ready',
    pages: [{ page_number: 1, text: 'A😀B passage' }],
    existing_content_hashes: [],
  })
  assert.equal(chunks?.length, 1)
  assert.equal(chunks?.[0].char_start, 0)
  // A, 😀, B, space, passage: PostgreSQL char_length is 11, while UTF-16 is 12.
  assert.equal(chunks?.[0].char_end, 11)
})

test('uses the effective event projection, including multiple financial years and a cleared scalar', async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  let embeddedText = ''
  const outcome = await runScopedSearchIndexReprocessWorker(workerClient(calls, {
    code: 'ready',
    doc_type: 'OIO',
    reference_number: 'CORRECTED/1',
    summary: 'Synthetic summary.',
    financial_years: ['2021-22', '2023-24'],
    issued_by: null,
    projection_fingerprint: 'a'.repeat(64),
  }), claim, corpusProvider(validCorpusEmbedding(), (request) => {
    embeddedText = request.input
    assert.equal(request.purpose, 'corpus')
  }))

  assert.deepEqual(outcome, { outcome: 'indexed' })
  assert.match(embeddedText, /Document type: OIO/)
  assert.match(embeddedText, /Reference: CORRECTED\/1/)
  assert.match(embeddedText, /FY 2021-22, 2023-24/)
  assert.doesNotMatch(embeddedText, /Issued by:/)
})

test('loads only a leased typed summary and completes the index through the fenced RPC', async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const outcome = await runScopedSearchIndexReprocessWorker(workerClient(calls), claim, corpusProvider(validCorpusEmbedding()))

  assert.deepEqual(outcome, { outcome: 'indexed' })
  assert.deepEqual(calls.map((call) => call.name), [
    'get_document_search_index_reprocess_input',
    'get_document_search_page_text_reprocess_input',
    'write_current_document_search_page_chunks',
    'finish_document_search_index_reprocess_work',
  ])
  assert.deepEqual(calls[0].args, {
    p_processing_run_id: claim.processing_run_id,
    p_lease_token: claim.lease_token,
  })
  assert.equal(calls[3].args.p_outcome, 'indexed')
  assert.equal(calls[3].args.p_projection_fingerprint, 'a'.repeat(64))
  assert.match(String(calls[3].args.p_embedding), /^\[(?:0\.1,){767}0\.1\]$/)
})

test('does not retry malformed or truncated embedding output and records only a safe failure', async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const outcome = await runScopedSearchIndexReprocessWorker(workerClient(calls), claim, corpusProvider({ ...validCorpusEmbedding(), truncated: true }))

  assert.deepEqual(outcome, { outcome: 'failed' })
  assert.equal(calls.at(-1)?.args.p_outcome, 'failed')
  assert.equal('p_embedding' in (calls.at(-1)?.args ?? {}), false)
})

test('requires the matching current source version and rejects truncated embeddings for either Search path', () => {
  assert.equal(hasCurrentSearchIndexEmbedding({
    embedding_model: 'gemini-embedding-001',
    embedding_version: 'gemini-embedding-001-768-v1',
    embedding_document_version_id: '50000000-0000-4000-8000-000000000002',
  }, claim.document_version_id), false)
  assert.equal(hasCurrentSearchIndexEmbedding({
    embedding_model: 'gemini-embedding-001',
    embedding_version: 'gemini-embedding-001-768-v1',
    embedding_document_version_id: claim.document_version_id,
  }, claim.document_version_id), true)
  assert.equal(serializeSearchIndexEmbedding({ ...validCorpusEmbedding(), truncated: true }), null)
})

test('rejects missing provider token usage and a mismatched configured model without a provider retry', async () => {
  for (const embedding of [
    { inputTokens: undefined as unknown as number, model: 'gemini-embedding-001' },
    { inputTokens: 7, model: 'unapproved-model' },
  ]) {
    const calls: Array<{ name: string; args: Record<string, unknown> }> = []
    const outcome = await runScopedSearchIndexReprocessWorker(workerClient(calls), claim, corpusProvider({
      ...validCorpusEmbedding(),
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
