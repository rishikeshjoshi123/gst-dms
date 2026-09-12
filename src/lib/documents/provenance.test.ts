import assert from 'node:assert/strict'
import test from 'node:test'
import { aiDocumentPayloadSchema, type AIDocumentPayload } from '@/lib/ai/schemas'
import { provenanceMaterializationFromAnalysis } from './provenance'

const providerPayload = {
  doc_type: 'SCN', document_title: null, document_class: 'proceeding', document_category: null,
  gstin: null, client_identifiers: null, client_name: null, doc_date: '2025-01-30',
  tax_periods: [{ kind: 'month', raw: 'JAN 2020 – JAN 2020', display: 'January 2020', precision: 'month',
    segments: [{ kind: 'month', month: '2020-01', quarter: null, financial_year: null, start_date: null, end_date: null }],
    printed_financial_years: ['2020-21'], source_page: 1, source_quote: 'Tax period JAN 2020 – JAN 2020', confidence: 0.96 }],
  official_references: [
    { role: 'self_identifier', kind: 'notice_reference', completeness: 'complete', namespace: 'cbic.gst', raw: 'SCN / 01', display: 'SCN/01',
      components: [{ name: 'serial', value: '01' }], source_page: 1, source_quote: 'Notice SCN / 01', confidence: 0.99 },
    { role: 'outbound_mention', kind: 'order_reference', completeness: 'complete', namespace: 'cbic.gst', raw: 'OIO / 09', display: 'OIO/09',
      components: [{ name: 'serial', value: '09' }], source_page: 2, source_quote: 'Against OIO / 09', confidence: 0.97 },
  ],
  direction: 'incoming', issued_by: null, summary: 'Synthetic notice.', deadlines: [],
  extracted_amounts: { tax: null, interest: null, penalty: null, fee: null, pre_deposit: null,
    total_demand: null, amount_in_dispute: null, amount_relief: null }, parties_named: [], legal_references: [],
  evidence: [
    { field: 'document_type', value: 'SCN', page_number: 1, quote: 'Show Cause Notice', confidence: 0.96 },
    { field: 'document_date', value: '2025-01-30', page_number: 1, quote: '30 January 2025', confidence: 0.92 },
    { field: 'direction', value: 'incoming', page_number: 1, quote: 'Incoming', confidence: 0.95 },
  ], confidence: 0.9,
}
const analysis = aiDocumentPayloadSchema.parse(providerPayload) as AIDocumentPayload
const pages = [
  { page_number: 1, text: 'Show Cause Notice. 30 January 2025. Incoming. Tax period JAN 2020 – JAN 2020. Notice SCN / 01', ocr_words: null },
  { page_number: 2, text: 'Against OIO / 09', ocr_words: null },
]

test('materializes typed periods and role-separated official references as immutable structured observations', () => {
  const result = provenanceMaterializationFromAnalysis(analysis, 2, pages)
  const period = result.candidates.find((candidate) => candidate.field_path === 'document.tax_period')
  const references = result.candidates.filter((candidate) => candidate.field_path.startsWith('document.official_reference.'))
  assert.equal(period?.value_type, 'structured')
  assert.equal(period?.validation_state, 'conflicting')
  assert.equal((period?.normalized_value as { conflict: boolean }).conflict, true)
  assert.deepEqual(references.map((candidate) => candidate.validation_state), ['provisional', 'provisional'])
  assert.notEqual(references[0].semantic_candidate_key, references[1].semantic_candidate_key)
  assert.ok(references.every((candidate) => candidate.verified_source_anchor !== null))
  assert.equal(result.reviewCodes.includes('printed_derived_financial_year_conflict'), true)
  assert.equal(result.reviewCodes.includes('unverified_official_reference'), true)
})

test('typed official references never materialize a legacy relationship candidate', () => {
  const result = provenanceMaterializationFromAnalysis(analysis, 2, pages)
  assert.equal(result.candidates.some((candidate) => candidate.field_path === 'document.referenced_document_number'), false)
})

test('missing canonical source makes a typed reference invalid without human verification', () => {
  const result = provenanceMaterializationFromAnalysis(analysis, 2, pages.slice(0, 1))
  const outbound = result.candidates.find((candidate) => candidate.field_path.endsWith('outbound_mention'))
  assert.equal(outbound?.validation_state, 'invalid')
  assert.deepEqual(outbound?.validation_error_codes, ['source_page_missing'])
})

test('out-of-bound evidence terminally rejects typed observations', () => {
  const unsafe = aiDocumentPayloadSchema.parse({ ...providerPayload,
    official_references: [{ ...providerPayload.official_references[0], source_page: 3 }] })
  const result = provenanceMaterializationFromAnalysis(unsafe, 2, pages)
  assert.equal(result.terminalReviewRequired, true)
  assert.equal(result.candidates.some((candidate) => candidate.field_path.startsWith('document.official_reference')), false)
})
