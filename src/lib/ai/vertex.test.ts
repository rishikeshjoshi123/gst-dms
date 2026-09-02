import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import {
  buildVertexEmbeddingRequest,
  resolveVertexDocumentLocation,
  resolveVertexEmbeddingLocation,
  validateVertexEmbeddingResponse,
} from './vertex'

test('Vertex structured-output boundary strictly parses complete JSON and logs only fixed diagnostics', () => {
  const source = readFileSync(new URL('./vertex.ts', import.meta.url), 'utf8')

  assert.match(source, /return JSON\.parse\(rawText\)/)
  assert.doesNotMatch(source, /indexOf\('\{'\)|lastIndexOf\('\}'\)|\.slice\(firstBrace/)
  assert.doesNotMatch(source, /console\.(?:error|warn)\([^\n]*,\s*(?:err|error|e|validation)/)
  assert.match(source, /logVertexDiagnostic\('document_response_unreadable'\)/)
  assert.match(source, /logVertexDiagnostic\('wiki_response_invalid'\)/)
})

test('Gemini SDK owns both structured document and legacy wiki generation contracts', () => {
  const source = readFileSync(new URL('./vertex.ts', import.meta.url), 'utf8')
  const document = source.slice(source.indexOf('export async function analyzeDocumentWithOutcome'), source.indexOf('/**\n * Transitional compatibility wrapper'))
  const wiki = source.slice(source.indexOf('export async function generateWikiSummary'), source.indexOf('// ── Embeddings'))

  for (const boundary of [document, wiki]) {
    assert.match(boundary, /gemini\.models\.generateContent\(/)
    assert.match(boundary, /responseMimeType: 'application\/json'/)
    assert.match(boundary, /responseSchema:/)
    assert.match(boundary, /response\.text\?\.trim\(\)/)
    assert.match(boundary, /extractJsonObject\(rawText\)/)
    assert.match(boundary, /safeParse\(/)
    assert.match(boundary, /usageFromResponse\(response\.usageMetadata\)/)
  }

  assert.match(wiki, /contents: buildWikiPrompt\(matterContext\)/)
  assert.match(wiki, /responseSchema: wikiResponseSchema/)
  assert.match(wiki, /temperature: 0\.1/)
  assert.match(wiki, /maxOutputTokens: 6144/)
  assert.doesNotMatch(wiki, /getVertexAI\(|preview\.getGenerativeModel|response\.response\.candidates/)
  assert.doesNotMatch(source, /@google-cloud\/vertexai|\bVertexAI\b/)
})

test('Vertex document and embedding locations are independently explicit and Mumbai-only', () => {
  assert.equal(resolveVertexDocumentLocation({ VERTEX_DOCUMENT_LOCATION: 'asia-south1' }), 'asia-south1')
  assert.equal(resolveVertexEmbeddingLocation({ VERTEX_EMBEDDING_LOCATION: 'asia-south1' }), 'asia-south1')
  assert.equal(resolveVertexDocumentLocation({ GOOGLE_CLOUD_REGION: 'us-central1' }), null)
  assert.equal(resolveVertexEmbeddingLocation({ VERTEX_EMBEDDING_LOCATION: 'global' }), null)
})

test('Gemini contract does not request a page transcript or OCR words', () => {
  const prompt = readFileSync(new URL('./prompts.ts', import.meta.url), 'utf8')
  const schema = readFileSync(new URL('./schemas.ts', import.meta.url), 'utf8')
  assert.doesNotMatch(prompt, /"page_text"|"ocr_words"/)
  assert.doesNotMatch(schema, /page_text|ocr_words/)
})

test('Vertex embedding provider uses distinct corpus, query, and similarity tasks', () => {
  assert.equal(buildVertexEmbeddingRequest({ input: 'corpus', purpose: 'corpus' }).instances[0].task_type, 'RETRIEVAL_DOCUMENT')
  assert.equal(buildVertexEmbeddingRequest({ input: 'query', purpose: 'query' }).instances[0].task_type, 'RETRIEVAL_QUERY')
  assert.equal(buildVertexEmbeddingRequest({ input: 'similarity', purpose: 'similarity' }).instances[0].task_type, 'SEMANTIC_SIMILARITY')
  assert.equal(buildVertexEmbeddingRequest({ input: 'query', purpose: 'query' }).parameters.autoTruncate, false)
})

test('Vertex embedding provider accepts only complete finite 768-dimensional provider-reported responses', () => {
  const response = {
    predictions: [{
      embeddings: {
        values: Array.from({ length: 768 }, () => 0.25),
        statistics: { token_count: 12, truncated: false },
      },
    }],
  }
  const accepted = validateVertexEmbeddingResponse(response, 'query')
  assert.deepEqual(accepted && {
    model: accepted.model,
    version: accepted.version,
    dimensions: accepted.dimensions,
    inputTokens: accepted.inputTokens,
    billableUsage: accepted.billableUsage,
    purpose: accepted.purpose,
  }, {
    model: 'gemini-embedding-001',
    version: 'gemini-embedding-001-768-v1',
    dimensions: 768,
    inputTokens: 12,
    billableUsage: null,
    purpose: 'query',
  })

  for (const invalid of [
    { ...response, predictions: [{ embeddings: { ...response.predictions[0].embeddings, values: Array.from({ length: 767 }, () => 0.25) } }] },
    { ...response, predictions: [{ embeddings: { ...response.predictions[0].embeddings, values: Array.from({ length: 769 }, () => 0.25) } }] },
    { ...response, predictions: [{ embeddings: { ...response.predictions[0].embeddings, values: [...response.predictions[0].embeddings.values.slice(0, 767), Number.NaN] } }] },
    { ...response, predictions: [{ embeddings: { ...response.predictions[0].embeddings, statistics: { token_count: 12, truncated: true } } }] },
    { ...response, predictions: [{ embeddings: { ...response.predictions[0].embeddings, statistics: { truncated: false } } }] },
  ]) assert.equal(validateVertexEmbeddingResponse(invalid, 'query'), null)

  const withReportedBilling = validateVertexEmbeddingResponse({
    ...response,
    predictions: [{ embeddings: {
      ...response.predictions[0].embeddings,
      statistics: { token_count: 12, truncated: false, billable_token_count: 9 },
    } }],
  }, 'query')
  assert.deepEqual(withReportedBilling?.billableUsage, { unit: 'tokens', quantity: 9 })
})
