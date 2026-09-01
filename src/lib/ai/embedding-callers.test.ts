import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

function source(relativePath: string) {
  return readFileSync(new URL(relativePath, import.meta.url), 'utf8')
}

test('live Search query caller uses query embeddings and preserves lexical fallback on provider failure', () => {
  const search = source('../actions/search.ts')

  assert.match(search, /vertexEmbeddingProvider\.embed\(\{ input: query, purpose: 'query' \}\)/)
  assert.match(search, /if \(aiResult\?\.embedding\)/)
  assert.match(search, /let vectorMatches: SearchDocumentRow\[\] = \[\]/)
})

test('the leased worker embeds corpus passages while matter reindex only queues the fenced authority', () => {
  const worker = source('../documents/scoped-reprocess.ts')
  const jobs = source('../../trigger/jobs.ts')

  assert.match(worker, /embed\.embed\(\{ input: text, purpose: 'corpus' \}\)/)
  assert.match(worker, /if \(!embedding \|\| !serializeSearchIndexEmbedding\(embedding\)\)/)
  assert.match(jobs, /enqueue_current_document_search_reindex/)
  assert.doesNotMatch(jobs, /write_current_document_search_index_embedding/)
  assert.doesNotMatch(jobs, /vertexEmbeddingProvider\.embed\(\{ input: embeddingText, purpose: 'corpus' \}\)/)
})
