import assert from 'node:assert/strict'
import test from 'node:test'
import { Type } from '@google/genai'
import { aiDocumentPayloadSchema, aiWikiPayloadSchema, documentResponseSchema, officialReferenceSemanticKey } from './schemas'

const segment = (kind: 'month' | 'quarter' | 'date_range' | 'financial_year', values: Record<string, string> = {}) => ({
  kind, month: null, quarter: null, financial_year: null, start_date: null, end_date: null, ...values,
})
const period = (kind: string, precision: string, segments: unknown[], raw = 'FY 2023-24', printed = ['2023-24']) => ({
  kind, raw, display: raw, precision, segments, printed_financial_years: printed,
  source_page: 1, source_quote: `Tax period ${raw}`, confidence: 0.96,
})
const validDocumentPayload = {
  doc_type: 'SCN', document_title: 'Show Cause Notice', document_class: 'proceeding', document_category: null,
  gstin: '27ABCDE1234F1Z5', client_identifiers: ['ABCDE1234F'], client_name: 'Example Private Limited',
  doc_date: '2024-04-01',
  tax_periods: [period('financial_year', 'financial_year', [segment('financial_year', { financial_year: '2023-24' })])],
  official_references: [{ role: 'self_identifier', kind: 'notice_reference', completeness: 'complete', namespace: 'cbic.gst',
    raw: 'SCN / 2024 / 001', display: 'SCN/2024/001', components: [{ name: 'serial', value: '001' }],
    source_page: 1, source_quote: 'SCN / 2024 / 001', confidence: 0.99 }],
  direction: 'incoming', issued_by: 'Deputy Commissioner',
  summary: 'The department alleges short payment of tax and asks the taxpayer to respond.',
  deadlines: [], extracted_amounts: { tax: null, interest: null, penalty: null, fee: null, pre_deposit: null,
    total_demand: null, amount_in_dispute: null, amount_relief: null }, parties_named: [], legal_references: [],
  evidence: [], confidence: 0.94,
}

test('canonical extraction derives legacy scalars and normalized references without accepting parallel provider fields', () => {
  const result = aiDocumentPayloadSchema.parse(validDocumentPayload)
  assert.equal(result.reference_number, 'SCN/2024/001')
  assert.deepEqual(result.financial_years, ['2023-24'])
  assert.deepEqual(result.chaining_attributes.references_documents, [])
  assert.equal(result.official_references[0].normalized_value, 'SCN/2024/001')
  assert.equal(result.official_references[0].catalogue_version, 'gst-document-and-official-reference-catalogue-v2')
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload, tax_period: 'legacy' }).success, false)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload, chaining_attributes: {} }).success, false)
})

test('tax periods retain source precision across all approved shapes without invented month bounds', () => {
  const periods = [
    period('month', 'month', [segment('month', { month: '2020-01' })], 'JAN 2020 – JAN 2020', []),
    period('quarter', 'quarter', [segment('quarter', { quarter: 'Q2', financial_year: '2021-22' })], 'Q2 FY 2021-22', ['2021-22']),
    period('exact_date_range', 'exact_date', [segment('date_range', { start_date: '2022-03-15', end_date: '2022-04-10' })], '15.03.2022 to 10.04.2022', []),
    period('financial_year', 'financial_year', [segment('financial_year', { financial_year: '2022-23' })], 'FY 2022-23', ['2022-23']),
    period('multi_financial_year', 'financial_year', [segment('financial_year', { financial_year: '2019-20' }), segment('financial_year', { financial_year: '2021-22' })], 'FY 2019-20 and FY 2021-22', ['2019-20', '2021-22']),
    period('non_contiguous', 'mixed', [segment('month', { month: '2020-01' }), segment('quarter', { quarter: 'Q4', financial_year: '2021-22' })], 'January 2020 and Q4 FY 2021-22', ['2021-22']),
    period('unclear', 'unclear', [], 'relevant period', []),
  ]
  const parsed = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, tax_periods: periods })
  assert.deepEqual(parsed.tax_periods.map((item) => item.kind), ['month', 'quarter', 'exact_date_range', 'financial_year', 'multi_financial_year', 'non_contiguous', 'unclear'])
  assert.deepEqual(parsed.tax_periods[0].segments[0], segment('month', { month: '2020-01' }))
  assert.deepEqual(parsed.tax_periods[0].derived_financial_years, ['2019-20'])
  assert.deepEqual(parsed.tax_periods[2].derived_financial_years, ['2021-22', '2022-23'])
})

test('printed and derived financial-year disagreement is deterministic field conflict data', () => {
  const parsed = aiDocumentPayloadSchema.parse({ ...validDocumentPayload,
    tax_periods: [period('month', 'month', [segment('month', { month: '2020-01' })], 'January 2020', ['2020-21'])] })
  assert.equal(parsed.tax_periods[0].conflict, true)
  assert.deepEqual(parsed.tax_periods[0].derived_financial_years, ['2019-20'])
  assert.deepEqual(parsed.tax_periods[0].printed_financial_years, ['2020-21'])

  const reordered = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, tax_periods: [period('multi_financial_year', 'financial_year', [
    segment('financial_year', { financial_year: '2022-23' }), segment('financial_year', { financial_year: '2021-22' }),
  ], 'FY 2022-23 and FY 2021-22', ['2021-22', '2022-23'])] })
  assert.equal(reordered.tax_periods[0].conflict, false)
  assert.deepEqual(reordered.tax_periods[0].derived_financial_years, ['2022-23', '2021-22'])
  assert.deepEqual(reordered.tax_periods[0].printed_financial_years, ['2021-22', '2022-23'])
})

test('official-reference semantic keys are bounded, stable, and role-separated', () => {
  const parsed = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, official_references: [
    validDocumentPayload.official_references[0],
    { ...validDocumentPayload.official_references[0], role: 'outbound_mention' },
  ] })
  const keys = parsed.official_references.map(officialReferenceSemanticKey)
  assert.match(keys[0], /^official_reference:self_identifier:[0-9a-f]{32}$/)
  assert.match(keys[1], /^official_reference:outbound_mention:[0-9a-f]{32}$/)
  assert.notEqual(keys[0], keys[1])
})

test('official references derive D09-T01 canonical namespace, value, and components without trusting model hints', () => {
  const adversarial = { ...validDocumentPayload.official_references[0], namespace: ' cbic . gst ',
    raw: 'SCN / 001 / 2026', display: 'SCN/001/2026', components: [{ name: 'year', value: '9999' }] }
  const normalized = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, official_references: [adversarial] }).official_references[0]
  assert.equal(normalized.namespace, 'cbic . gst')
  assert.equal(normalized.namespace_normalized, 'CBIC.GST')
  assert.equal(normalized.normalized_value, 'SCN/001/2026')
  assert.deepEqual(normalized.components, { kind: 'notice_reference', segments: ['SCN', '001', '2026'],
    prefix: 'SCN', numericCore: '001', year: '2026' })
  assert.equal(normalized.match_eligible, true)

  const canonicalDuplicate = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, official_references: [{ ...adversarial,
    namespace: 'CBIC.GST', raw: 'SCN/001/2026', components: [] }] }).official_references[0]
  assert.equal(officialReferenceSemanticKey(normalized), officialReferenceSemanticKey(canonicalDuplicate))

  const punctuation = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, official_references: [{ ...adversarial,
    raw: 'ＳＣＮ ‐ 001 / 2026', display: 'SCN-001/2026' }] }).official_references[0]
  assert.equal(punctuation.normalized_value, 'SCN-001/2026')
  assert.deepEqual(punctuation.components.segments, ['SCN', '001', '2026'])

  const mixedDigits = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, official_references: [{ ...adversarial,
    raw: 'ＳＣＮ ‐ ٠٠١ / ２０２６', display: 'SCN-٠٠١/2026' }] }).official_references[0]
  assert.equal(mixedDigits.normalized_value, 'SCN-٠٠١/2026')
  assert.deepEqual(mixedDigits.components, { kind: 'notice_reference', segments: ['SCN', '٠٠١', '2026'],
    prefix: 'SCN', numericCore: '2026', year: '2026' })
})

test('unknown, partial, and uncatalogued official references are retained but never match eligible', () => {
  const references = [
    { ...validDocumentPayload.official_references[0], namespace: null, completeness: 'unknown' },
    { ...validDocumentPayload.official_references[0], completeness: 'partial' },
    { ...validDocumentPayload.official_references[0], kind: 'other_official_reference' },
  ]
  const document = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, official_references: references })
  assert.deepEqual(document.official_references.map((reference) => reference.match_eligible), [false, false, false])
  assert.equal(document.official_references[0].namespace_normalized, null)
  assert.equal(document.official_references[0].normalized_value, 'SCN/2024/001')
  assert.equal(document.reference_number, null)
  assert.deepEqual(document.chaining_attributes.references_documents, [])
})

test('Vertex provider schema is recursively derived from canonical input while Zod rejects drift', () => {
  assert.equal(documentResponseSchema.type, Type.OBJECT)
  assert.deepEqual(documentResponseSchema.required, Object.keys(documentResponseSchema.properties!))
  assert.ok(documentResponseSchema.properties?.tax_periods)
  assert.ok(documentResponseSchema.properties?.official_references)
  assert.equal(documentResponseSchema.properties?.reference_number, undefined)
  assert.equal(documentResponseSchema.properties?.chaining_attributes, undefined)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload, invented_legal_opinion: 'will win' }).success, false)
})

test('rejects malformed period/reference structures and transcript fields', () => {
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    tax_periods: [period('month', 'month', [segment('month', { month: '2020-01', start_date: '2020-01-01' })])] }).success, false)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    official_references: [{ ...validDocumentPayload.official_references[0], role: 'parent' }] }).success, false)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    tax_periods: [period('financial_year', 'financial_year', [segment('financial_year', { financial_year: '2023-99' })], 'FY 2023-99', ['2023-99'])] }).success, false)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload, page_text: [] }).success, false)
})

test('rejects control characters before typed source fields can be normalized or persisted', () => {
  const reference = validDocumentPayload.official_references[0]
  const typedReferenceFields = [
    { ...reference, raw: 'SCN\n001' }, { ...reference, raw: '\nSCN001' }, { ...reference, display: 'SCN\n001' },
    { ...reference, namespace: 'cbic\ngst' }, { ...reference, source_quote: 'SCN\n001' },
  ]
  for (const candidate of typedReferenceFields) {
    assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload, official_references: [candidate] }).success, false)
  }
  const typedPeriodFields = [
    period('month', 'month', [segment('month', { month: '2020-01' })], 'JAN\n2020', []),
    { ...period('month', 'month', [segment('month', { month: '2020-01' })], 'JAN 2020', []), display: 'JAN\n2020' },
    { ...period('month', 'month', [segment('month', { month: '2020-01' })], 'JAN 2020', []), source_quote: 'JAN\n2020' },
  ]
  for (const candidate of typedPeriodFields) {
    assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload, tax_periods: [candidate] }).success, false)
  }
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    evidence: [{ field: 'document_type', value: 'SCN\n001', page_number: 1, quote: 'SCN', confidence: 0.9 }] }).success, false)
})

test('validates the current Case Brief storage contract', () => {
  assert.equal(aiWikiPayloadSchema.safeParse({ executive_summary: 'Summary.', key_arguments: 'Arguments.', outstanding_tasks: 'Tasks.' }).success, true)
})
