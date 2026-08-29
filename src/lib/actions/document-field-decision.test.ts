import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { replacementValue } from '@/lib/documents/inspector-field-correction'

test('serializes only valid typed inspector corrections', () => {
  assert.equal(replacementValue('financial.tax', '1200.50'), '1200.50')
  assert.equal(replacementValue('financial.tax', '1,200.50'), null)
  assert.equal(replacementValue('document.date', '2026-08-30'), '2026-08-30')
  assert.equal(replacementValue('document.date', '30/08/2026'), null)
  assert.equal(replacementValue('document.reference_number', '  SCN/123  '), 'SCN/123')
  assert.equal(replacementValue('document.reference_number', '   '), null)
  assert.equal(replacementValue('document.financial_year', ' 2024-25 '), '2024-25')
})
test('uses only the atomic service correction authority', () => {
  const source = readFileSync(new URL('./document-field-decision.ts', import.meta.url), 'utf8')
  assert.match(source, /record_current_document_inspector_correction/)
  assert.doesNotMatch(source, /\.from\('document_field_candidates'\)/)
  assert.doesNotMatch(source, /raw_metadata/)
})
