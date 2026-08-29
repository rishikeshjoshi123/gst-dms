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
  assert.deepEqual(result.reviewCodes, ['provisional_evidence'])
})

test('missing page or quotation never becomes a candidate and opens a safe review exception', () => {
  const result = provenanceMaterializationFromAnalysis({
    ...analysis,
    evidence: analysis.evidence.map((item) => item.field === 'document_type' ? { ...item, quote: null } : item),
  }, 2)
  assert.equal(result.candidates.some((candidate) => candidate.semantic_candidate_key === 'document.type'), false)
  assert.equal(result.reviewCodes.includes('missing_evidence'), true)
})

test('routes page-bound evidence outside the immutable asset boundary to terminal Review', () => {
  const result = provenanceMaterializationFromAnalysis({
    ...analysis,
    evidence: analysis.evidence.map((item) => item.field === 'document_type' ? { ...item, page_number: 3 } : item),
  }, 2)
  assert.equal(result.terminalReviewRequired, true)
  assert.equal(result.candidates.some((candidate) => candidate.semantic_candidate_key === 'document.type'), false)
})
