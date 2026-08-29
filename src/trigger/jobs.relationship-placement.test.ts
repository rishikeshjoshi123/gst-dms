import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

test('processDocument places validated and already-validated work through the typed effective relationship command', () => {
  const allSource = readFileSync(new URL('./jobs.ts', import.meta.url), 'utf8')
  const source = allSource.slice(allSource.indexOf('export const processDocument'), allSource.indexOf('// Versioned embedding backfill'))
  const placementHelper = allSource.slice(
    allSource.indexOf('async function placeValidatedDocumentRelationships'),
    allSource.indexOf('async function beginProvenanceExtraction'),
  )

  assert.match(allSource, /placeProcessingDocumentRelationships\(supabase, \{[\s\S]*p_document_version_id/)
  assert.match(placementHelper, /placement\?\.code === 'target_snapshot_busy'[\s\S]*throw new Error\('Document relationship placement target snapshot busy'\)/)
  assert.doesNotMatch(placementHelper, /needs_review/)
  assert.match(source, /started\?\.code === 'already_validated'[\s\S]*placeValidatedDocumentRelationships/)
  assert.match(source, /completed\.code === 'review_required'\) return[\s\S]*placeValidatedDocumentRelationships/)
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
