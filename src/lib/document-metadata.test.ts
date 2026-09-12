import assert from 'node:assert/strict'
import test from 'node:test'
import type { AIDocumentResult } from '@/lib/ai/vertex'
import { documentColumnsFromAnalysis } from './document-metadata'

const analysis: AIDocumentResult = {
  doc_type: 'SCN',
  document_title: 'Show Cause Notice',
  document_class: 'proceeding',
  document_category: null,
  reference_number: 'SCN/E2E/UPLOAD/001',
  gstin: '27ABCDE1234F1Z5',
  client_identifiers: ['27ABCDE1234F1Z5'],
  client_name: null,
  doc_date: '2024-04-01',
  financial_years: ['2024-25'],
  tax_periods: [{ kind: 'financial_year', raw: 'FY 2024-25', display: 'FY 2024-25', precision: 'financial_year',
    segments: [{ kind: 'financial_year', month: null, quarter: null, financial_year: '2024-25', start_date: null, end_date: null }],
    financial_years: ['2024-25'], printed_financial_years: ['2024-25'], derived_financial_years: ['2024-25'], conflict: false,
    source_page: 1, source_quote: 'FY 2024-25', confidence: 0.9,
    catalogue_version: 'gst-document-and-official-reference-catalogue-v2', normalizer_version: 'typed-period-reference-normalizer-v2' }],
  official_references: [{ role: 'self_identifier', kind: 'notice_reference', completeness: 'complete', namespace: 'cbic.gst',
    namespace_normalized: 'CBIC.GST', raw: 'SCN/E2E/UPLOAD/001', display: 'SCN/E2E/UPLOAD/001',
    normalized_value: 'SCN/E2E/UPLOAD/001', components: { kind: 'notice_reference', segments: ['SCN','E2E','UPLOAD','001'], prefix: 'SCN', numericCore: '001' }, match_eligible: true, source_page: 1,
    source_quote: 'SCN/E2E/UPLOAD/001', confidence: 0.9, catalogue_version: 'gst-document-and-official-reference-catalogue-v2',
    normalizer_version: 'typed-period-reference-normalizer-v2' }],
  direction: 'incoming',
  issued_by: 'Deputy Commissioner',
  summary: 'Synthetic test notice.',
  chaining_attributes: {
    references_documents: [],
    gstin: '27ABCDE1234F1Z5',
    financial_years: ['2024-25'],
    matter_ref: null,
    link_type: null,
  },
  deadlines: [],
  extracted_amounts: {
    tax: null, interest: null, penalty: null, fee: null, pre_deposit: null,
    total_demand: null, amount_in_dispute: null, amount_relief: null,
  },
  parties_named: [],
  legal_references: [],
  evidence: [],
  confidence: 0.9,
  prompt_version: 'test',
}

test('copies analysis fields needed by timeline and details into document columns', () => {
  const columns = documentColumnsFromAnalysis(analysis, '2024-25')

  assert.equal(columns.doc_type, 'SCN')
  assert.equal(columns.reference_number, 'SCN/E2E/UPLOAD/001')
  assert.equal(columns.doc_date, '2024-04-01')
  assert.equal(columns.issued_by, 'Deputy Commissioner')
  assert.equal(columns.summary, 'Synthetic test notice.')
  assert.equal(columns.financial_year, '2024-25')
  assert.equal(columns.raw_metadata, analysis)
})

test('uses display-safe defaults for omitted optional analysis fields', () => {
  const columns = documentColumnsFromAnalysis({
    ...analysis,
    doc_type: null,
    reference_number: null,
    doc_date: null,
    issued_by: null,
    summary: '',
    direction: null,
    document_category: null,
  }, null)

  assert.deepEqual(columns, {
    doc_type: 'OTHER',
    reference_number: null,
    doc_date: null,
    direction: 'incoming',
    issued_by: null,
    document_class: 'proceeding',
    document_category: null,
    financial_year: null,
    summary: null,
    raw_metadata: columns.raw_metadata,
  })
})
