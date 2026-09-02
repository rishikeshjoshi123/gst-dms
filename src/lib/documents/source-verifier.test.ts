import assert from 'node:assert/strict'
import test from 'node:test'

import { verifyCanonicalSource, type CanonicalPage } from './source-verifier'

const gstin = '27AAPFU0939F1ZV'
const page = (text: string, words: CanonicalPage['ocr_words'] = null): CanonicalPage => ({ page_number: 1, text, ocr_words: words })

test('verifies one exact GSTIN quote and persists only canonical token regions', () => {
  const result = verifyCanonicalSource(page(`GSTIN: ${gstin}`, [
    { text: 'GSTIN:', x: 0.1, y: 0.1, width: 0.1, height: 0.05 },
    { text: gstin, x: 0.21, y: 0.1, width: 0.2, height: 0.05 },
  ]), `GSTIN: ${gstin}`, gstin, 'code', 'gstin')
  assert.equal(result.ok, true)
  if (result.ok) assert.deepEqual(result.evidence, {
    char_start: 0, char_end: 22, token_start: 0, token_end: 1,
    table_cell: null,
    regions: [
      { x: 0.1, y: 0.1, width: 0.1, height: 0.05 },
      { x: 0.21, y: 0.1, width: 0.2, height: 0.05 },
    ],
  })
})

test('rejects repeated source values, quote ambiguity, one-digit mismatches, and invalid identifiers', () => {
  assert.equal(verifyCanonicalSource(page(`GSTIN ${gstin}; previous GSTIN ${gstin}`), gstin, gstin, 'code', 'gstin').ok, false)
  assert.equal(verifyCanonicalSource(page(`Reference ABC/123 and Reference ABC/123`), 'Reference ABC/123', 'ABC/123', 'text').ok, false)
  assert.equal(verifyCanonicalSource(page(`GSTIN ${gstin}`), gstin, '27AAPFU0939F1ZW', 'code', 'gstin').ok, false)
  assert.deepEqual(verifyCanonicalSource(page('PAN ABCDE1234F'), 'PAN ABCDE1234F', 'ABCDE1234F', 'code', 'gstin'), { ok: false, code: 'invalid_identifier' })
})

test('requires one complete normalized code, text, or decimal token', () => {
  assert.deepEqual(
    verifyCanonicalSource(page('Total 1,000.50'), 'Total 1,000.50', '1000', 'decimal'),
    { ok: false, code: 'value_not_in_quote' },
  )
  assert.deepEqual(
    verifyCanonicalSource(page('Reference XABC/123'), 'Reference XABC/123', 'ABC/123', 'code'),
    { ok: false, code: 'value_not_in_quote' },
  )
  assert.deepEqual(
    verifyCanonicalSource(page('Reference ABC/123; again ABC/123'), 'Reference ABC/123; again ABC/123', 'ABC/123', 'code'),
    { ok: false, code: 'value_not_in_quote' },
  )
})

test('normalizes supported calendar dates and does not fabricate regions without canonical word alignment', () => {
  const result = verifyCanonicalSource(page('Reply is due on 29.01.2025.'), 'Reply is due on 29.01.2025', '2025-01-29', 'date')
  assert.equal(result.ok, true)
  if (result.ok) assert.deepEqual(result.evidence.regions, [])
  assert.equal(verifyCanonicalSource(page('Reply is due on 29 January 2025.'), '29 January 2025', '2025-01-29', 'date').ok, true)
  assert.equal(verifyCanonicalSource(page('Reply is due on January 29, 2025.'), 'January 29, 2025', '2025-01-29', 'date').ok, true)
  assert.deepEqual(verifyCanonicalSource(page('Reply is due on 29 February 2025.'), '29 February 2025', '2025-02-29', 'date'), { ok: false, code: 'invalid_date' })
  assert.deepEqual(verifyCanonicalSource(page('Invalid 31.02.2025'), 'Invalid 31.02.2025', '2025-02-31', 'date'), { ok: false, code: 'invalid_date' })
})

test('uses one retained table cell and its canonical box only when the source value is unique', () => {
  const result = verifyCanonicalSource({
    page_number: 1,
    text: 'Total amount 1,000.',
    ocr_words: null,
    table_cells: [{
      table_index: 0, row_index: 1, column_index: 1, row_span: 1, column_span: 1, reading_order: 3,
      text: 'Total amount 1,000', x: 0.4, y: 0.3, width: 0.2, height: 0.05,
    }],
  }, 'Total amount 1,000', '1000', 'decimal')

  assert.equal(result.ok, true)
  if (result.ok) assert.deepEqual(result.evidence, {
    char_start: 0, char_end: 18, token_start: null, token_end: null,
    table_cell: { table_index: 0, row_index: 1, column_index: 1 },
    regions: [{ x: 0.4, y: 0.3, width: 0.2, height: 0.05 }],
  })

  assert.deepEqual(verifyCanonicalSource({
    page_number: 1,
    text: 'Tax payable 1,000. Total amount 1,000.',
    ocr_words: null,
    table_cells: [{
      table_index: 0, row_index: 1, column_index: 1, row_span: 1, column_span: 1, reading_order: 3,
      text: 'Total amount 1,000', x: 0.4, y: 0.3, width: 0.2, height: 0.05,
    }],
  }, 'Total amount 1,000', '1000', 'decimal'), { ok: false, code: 'ambiguous_source_match' })
})
