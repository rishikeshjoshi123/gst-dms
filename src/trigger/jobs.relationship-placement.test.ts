import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

test('D09-T03 extraction never invokes legacy relationship placement', () => {
  const allSource = readFileSync(new URL('./jobs.ts', import.meta.url), 'utf8')
  const source = allSource.slice(allSource.indexOf('export const processDocument'), allSource.indexOf('// Versioned embedding backfill'))
  assert.doesNotMatch(source, /placeValidatedDocumentRelationships|placeProcessingDocumentRelationships|place_document_processing_relationships/)
  assert.match(source, /D09-T03 observations are deliberately inert/)
  assert.match(source, /started\?\.code === 'already_validated'[\s\S]*status: 'placed'/)
  assert.match(source, /completed\.code === 'review_required'\) return[\s\S]*status: 'placed'/)
  assert.match(source, /retry: \{[\s\S]*maxAttempts: 3/)
  assert.doesNotMatch(source, /placeDocument\(/)
  assert.doesNotMatch(source, /raw_metadata|AIDocumentResult|chaining_attributes/)
})

test('the typed placement helper has no browser authorisation wrapper or AI payload adapter', () => {
  const source = readFileSync(new URL('../lib/documents/matter-relationship-effective-metadata.ts', import.meta.url), 'utf8')
  const placement = source.slice(source.indexOf('export async function placeProcessingDocumentRelationships'))

  assert.match(placement, /supabase\.rpc\('place_document_processing_relationships', args\)/)
  assert.doesNotMatch(placement, /createClient|getCurrentOrgId|raw_metadata|AIDocumentResult/)
})

test('processDocument writes the fenced page artifact from native/OCR acquisition, never Gemini output', () => {
  const source = readFileSync(new URL('./jobs.ts', import.meta.url), 'utf8')
  const documentWorker = source.slice(source.indexOf('export const processDocument'), source.indexOf('// Versioned embedding backfill'))

  assert.match(documentWorker, /acquireDocumentPageText\(fileBuffer, Number\(started\.page_count\)\)/)
  assert.match(documentWorker, /pageAcquisition\.kind === 'complete' \? pageAcquisition\.pages/)
  assert.doesNotMatch(documentWorker, /modelOutcome\.result\.page_text|modelOutcome\.result\.ocr_words/)
})
