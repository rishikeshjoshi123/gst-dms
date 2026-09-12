import assert from 'node:assert/strict'
import test from 'node:test'
import { aiDocumentPayloadSchema } from '@/lib/ai/schemas'
import type { AIDocumentResult } from '@/lib/ai/vertex'
import { documentColumnsFromAnalysis } from './document-metadata'

const observed = (raw: string, extras: Record<string, unknown>) => ({ raw, display: raw, precision: 'exact', source_page: 1, source_quote: raw, confidence: 0.9, ...extras })
const parsed = aiDocumentPayloadSchema.parse({
  doc_type: 'SCN', document_title: 'Show Cause Notice', document_class: 'proceeding', document_category: null,
  client_identifiers_observed: [observed('27AAPFU0939F1ZV', { kind: 'gstin', catalogue_kind: null })], client_name: null,
  legal_dates: [observed('1 April 2024', { meaning: 'issue', normalized_date: '2024-04-01' })],
  actors: [
    observed('Deputy Commissioner', { actor_kind: 'issuer', procedural_role: 'authority', authority: 'GST Department', office: null, jurisdiction: null }),
    observed('Taxpayer', { actor_kind: 'recipient', procedural_role: 'taxpayer', authority: null, office: null, jurisdiction: null }),
  ],
  tax_periods: [{ kind: 'financial_year', raw: 'FY 2024-25', display: 'FY 2024-25', precision: 'financial_year',
    segments: [{ kind: 'financial_year', month: null, quarter: null, financial_year: '2024-25', start_date: null, end_date: null }],
    printed_financial_years: ['2024-25'], source_page: 1, source_quote: 'FY 2024-25', confidence: 0.9 }],
  official_references: [{ role: 'self_identifier', kind: 'notice_reference', completeness: 'complete', namespace: 'cbic.gst',
    raw: 'SCN/E2E/UPLOAD/001', display: 'SCN/E2E/UPLOAD/001', components: [], source_page: 1, source_quote: 'SCN/E2E/UPLOAD/001', confidence: 0.9 }],
  money_observations: [], parties: [], legal_provisions: [], summary: 'Synthetic test notice.', evidence: [], confidence: 0.9,
})
const analysis: AIDocumentResult = { ...parsed, prompt_version: 'test' }

test('copies derived analysis fields needed by timeline and details into document columns', () => {
  const columns = documentColumnsFromAnalysis(analysis, '2024-25')
  assert.equal(columns.doc_type, 'SCN')
  assert.equal(columns.reference_number, 'SCN/E2E/UPLOAD/001')
  assert.equal(columns.doc_date, '2024-04-01')
  assert.equal(columns.direction, 'incoming')
  assert.equal(columns.issued_by, 'Deputy Commissioner')
  assert.equal(columns.summary, 'Synthetic test notice.')
  assert.equal(columns.financial_year, '2024-25')
  assert.equal(columns.raw_metadata, analysis)
})

test('preserves unknown derived direction as null', () => {
  const columns = documentColumnsFromAnalysis({ ...analysis, doc_type: null, direction: null, issued_by: null, doc_date: null, summary: '', document_category: null }, null)
  assert.deepEqual(columns, {
    doc_type: 'OTHER', reference_number: 'SCN/E2E/UPLOAD/001', doc_date: null, direction: null,
    issued_by: null, document_class: 'proceeding', document_category: null, financial_year: null,
    summary: null, raw_metadata: columns.raw_metadata,
  })
})
