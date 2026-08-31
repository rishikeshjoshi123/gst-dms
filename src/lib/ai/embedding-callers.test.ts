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

test('leased worker and matter reindex use corpus embeddings and fail without writing invalid responses', () => {
  const worker = source('../documents/scoped-reprocess.ts')
  const jobs = source('../../trigger/jobs.ts')

  assert.match(worker, /embed\.embed\(\{ input: text, purpose: 'corpus' \}\)/)
  assert.match(worker, /if \(!embedding \|\| !serializeSearchIndexEmbedding\(embedding\)\)/)
  assert.match(jobs, /vertexEmbeddingProvider\.embed\(\{ input: embeddingText, purpose: 'corpus' \}\)/)
  assert.match(jobs, /if \(!embedding \|\| !result\)/)
})
