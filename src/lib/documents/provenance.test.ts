import assert from 'node:assert/strict'
import test from 'node:test'
import type { AIDocumentPayload } from '@/lib/ai/schemas'
import { provenanceMaterializationFromAnalysis } from './provenance'

const analysis: AIDocumentPayload = {
  doc_type: 'SCN', document_title: null, document_class: 'proceeding', document_category: null,
  reference_number: 'SCN/01', gstin: null, client_identifiers: null, client_name: null,
  doc_date: '2025-01-30', financial_years: ['2024-25'], tax_period: null,
  direction: 'incoming', issued_by: null, summary: 'Synthetic notice.',
  chaining_attributes: { references_documents: [], gstin: null, financial_years: [], matter_ref: null, link_type: null },
  deadlines: [], extracted_amounts: {
    tax: null, interest: null, penalty: null, fee: null, pre_deposit: null,
    total_demand: null, amount_in_dispute: null, amount_relief: null,
  }, parties_named: [], legal_references: [], confidence: 0.9,
  evidence: [
    { field: 'document_type', value: 'SCN', page_number: 1, quote: 'Show Cause Notice', confidence: 0.96 },
    { field: 'reference_number', value: 'SCN/01', page_number: 1, quote: 'SCN/01', confidence: 0.91 },
    { field: 'document_date', value: '2025-01-30', page_number: 1, quote: '30 January 2025', confidence: 0.92 },
    { field: 'financial_year', value: '2024-25', page_number: 2, quote: 'FY 2024-25', confidence: 0.65 },
    { field: 'direction', value: 'incoming', page_number: 1, quote: 'Commissioner of State Tax', confidence: 0.95 },
  ],
}

test('materializes only evidence-bound scalar candidates and preserves provisional state', () => {
  const result = provenanceMaterializationFromAnalysis(analysis, 2)
  assert.deepEqual(result.candidates.map((candidate) => candidate.semantic_candidate_key), [
    'document.type', 'document.reference_number', 'document.date', 'document.direction', 'financial_year:0',
  ])
  assert.equal(result.candidates.at(-1)?.validation_state, 'provisional')
  assert.equal(result.reviewRequired, true)
  assert.deepEqual(result.reviewCodes, ['provisional_evidence', 'source_page_missing'])
})

test('missing page or quotation never becomes a candidate and opens a safe review exception', () => {
  const result = provenanceMaterializationFromAnalysis({
    ...analysis,
    evidence: analysis.evidence.map((item) => item.field === 'document_type' ? { ...item, quote: null } : item),
  }, 2)
  assert.equal(result.candidates.some((candidate) => candidate.semantic_candidate_key === 'document.type'), false)
  assert.equal(result.reviewCodes.includes('missing_evidence'), true)
})

test('marks critical facts invalid when canonical page acquisition is unavailable', () => {
  const result = provenanceMaterializationFromAnalysis({
    ...analysis,
    doc_date: null,
    financial_years: [],
    evidence: analysis.evidence.filter((item) => item.field === 'document_type' || item.field === 'reference_number'),
  }, 2)
  const reference = result.candidates.find((candidate) => candidate.semantic_candidate_key === 'document.reference_number')

  assert.deepEqual(reference && {
    validation_state: reference.validation_state,
    validation_error_codes: reference.validation_error_codes,
    verified_source_anchor: reference.verified_source_anchor,
    evidence_regions: reference.evidence_regions,
  }, {
    validation_state: 'invalid',
    validation_error_codes: ['source_page_missing'],
    verified_source_anchor: null,
    evidence_regions: null,
  })
  assert.equal(result.reviewCodes.includes('source_page_missing'), true)
})

test('materializes source-verified generic client identifiers without treating them as GSTIN or PAN', () => {
  const result = provenanceMaterializationFromAnalysis({
    ...analysis,
    client_identifiers: ['CLIENT-REG-42'],
    chaining_attributes: { ...analysis.chaining_attributes, references_documents: [] },
    evidence: [
      ...analysis.evidence,
      { field: 'client_identifier', value: 'CLIENT-REG-42', page_number: 1, quote: 'Client registration CLIENT-REG-42', confidence: 0.95 },
    ],
  }, 2, [{ page_number: 1, text: 'Client registration CLIENT-REG-42', ocr_words: null }])

  const identifier = result.candidates.find((candidate) => candidate.field_path === 'document.client_identifier')
  assert.deepEqual(identifier && {
    validation_state: identifier.validation_state,
    validation_error_codes: identifier.validation_error_codes,
    verified_source_anchor: identifier.verified_source_anchor,
  }, {
    validation_state: 'eligible',
    validation_error_codes: null,
    verified_source_anchor: { char_start: 0, char_end: 33, token_start: null, token_end: null, table_cell: null },
  })
})

test('routes page-bound evidence outside the immutable asset boundary to terminal Review', () => {
  const result = provenanceMaterializationFromAnalysis({
    ...analysis,
    evidence: analysis.evidence.map((item) => item.field === 'document_type' ? { ...item, page_number: 3 } : item),
  }, 2)
  assert.equal(result.terminalReviewRequired, true)
  assert.equal(result.candidates.some((candidate) => candidate.semantic_candidate_key === 'document.type'), false)
})
