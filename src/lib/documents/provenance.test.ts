import assert from 'node:assert/strict'
import test from 'node:test'
import { aiDocumentPayloadSchema, type AIDocumentPayload } from '@/lib/ai/schemas'
import { provenanceMaterializationFromAnalysis } from './provenance'

const observed = (raw: string, sourcePage: number, extras: Record<string, unknown>) => ({
  raw, display: raw, precision: 'exact', source_page: sourcePage, source_quote: raw, confidence: 0.96, ...extras,
})
const providerPayload = {
  doc_type: 'SCN', document_title: null, document_class: 'proceeding', document_category: null,
  client_identifiers_observed: [
    observed('27AAPFU0939F1ZV', 1, { kind: 'gstin', catalogue_kind: null }),
    observed('27AAPFU0939F1ZU', 1, { kind: 'gstin', catalogue_kind: null }),
  ],
  client_name: null,
  legal_dates: [
    observed('30 January 2025', 1, { meaning: 'issue', normalized_date: '2025-01-30' }),
    observed('31 February 2025', 1, { meaning: 'hearing', normalized_date: '2025-02-31' }),
  ],
  actors: [
    observed('Deputy Commissioner', 1, { actor_kind: 'issuer', procedural_role: 'authority', authority: 'GST Department', office: 'Division I', jurisdiction: 'Mumbai', source_quote: 'Deputy Commissioner, GST Department, Division I, Mumbai' }),
    observed('Example Private Limited', 1, { actor_kind: 'recipient', procedural_role: 'taxpayer', authority: null, office: null, jurisdiction: null }),
  ],
  tax_periods: [{ kind: 'month', raw: 'JAN 2020 – JAN 2020', display: 'January 2020', precision: 'month',
    segments: [{ kind: 'month', month: '2020-01', quarter: null, financial_year: null, start_date: null, end_date: null }],
    printed_financial_years: ['2020-21'], source_page: 1, source_quote: 'Tax period JAN 2020 – JAN 2020', confidence: 0.96 }],
  official_references: [
    { role: 'self_identifier', kind: 'notice_reference', completeness: 'complete', namespace: 'cbic.gst', raw: 'SCN / 01', display: 'SCN/01',
      components: [{ name: 'serial', value: '01' }], source_page: 1, source_quote: 'Notice SCN / 01', confidence: 0.99 },
    { role: 'outbound_mention', kind: 'order_reference', completeness: 'complete', namespace: 'cbic.gst', raw: 'OIO / 09', display: 'OIO/09',
      components: [{ name: 'serial', value: '09' }], source_page: 2, source_quote: 'Against OIO / 09', confidence: 0.97 },
  ],
  money_observations: [observed('₹ 9,007,199,254,740,993,123.67', 2, { representation: 'decimal', amount: '9007199254740993123.67', currency: 'INR', component: 'tax', applicable_period_reference: 'JAN 2020', legal_posture: 'alleged' })],
  parties: [observed('Example Private Limited', 1, { procedural_role: 'taxpayer' })],
  legal_provisions: [observed('Section 73 of CGST Act', 2, { act_kind: 'cgst_act', act: 'CGST Act', provision_kind: 'section', provision_value: '73' })],
  summary: 'Synthetic notice.', evidence: [{ field: 'document_type', value: 'SCN', page_number: 1, quote: 'Show Cause Notice', confidence: 0.96 }], confidence: 0.9,
}
const analysis = aiDocumentPayloadSchema.parse(providerPayload) as AIDocumentPayload
const pages = [
  { page_number: 1, text: 'Show Cause Notice. 30 January 2025. 31 February 2025. 27AAPFU0939F1ZV. 27AAPFU0939F1ZU. Deputy Commissioner, GST Department, Division I, Mumbai. Example Private Limited. Tax period JAN 2020 – JAN 2020. Notice SCN / 01', ocr_words: null },
  { page_number: 2, text: 'Against OIO / 09. ₹ 9,007,199,254,740,993,123.67. Section 73 of CGST Act', ocr_words: null },
]

test('materializes every material family as structured source observations with no legacy scalar duplicates', () => {
  const result = provenanceMaterializationFromAnalysis(analysis, 2, pages)
  const paths = result.candidates.map((candidate) => candidate.field_path)
  assert.ok(paths.includes('document.client_identifier.gstin'))
  assert.ok(paths.includes('document.legal_date.issue'))
  assert.ok(paths.includes('document.actor.issuer'))
  assert.ok(paths.includes('document.party.taxpayer'))
  assert.ok(paths.includes('document.money.tax'))
  assert.ok(paths.includes('document.legal_provision.section'))
  assert.ok(result.candidates.filter((candidate) => paths.includes(candidate.field_path)).every((candidate) => candidate.value_type === 'structured' || candidate.field_path === 'document.type'))
  for (const legacyPath of ['document.gstin', 'document.client_identifier', 'document.date', 'document.direction', 'document.issued_by', 'deadline.due_date', 'financial.tax', 'legal_reference.provision_number']) {
    assert.equal(paths.includes(legacyPath), false)
  }
})

test('invalid one-character GSTIN/date remain field-local invalid candidates with source anchors', () => {
  const result = provenanceMaterializationFromAnalysis(analysis, 2, pages)
  const gstins = result.candidates.filter((candidate) => candidate.field_path === 'document.client_identifier.gstin')
  assert.deepEqual(gstins.map((candidate) => candidate.validation_state), ['provisional', 'invalid'])
  assert.equal((gstins[1].normalized_value as { normalized_value: string | null }).normalized_value, null)
  assert.deepEqual(gstins[1].validation_error_codes, ['invalid_gstin'])
  assert.ok(gstins.every((candidate) => candidate.verified_source_anchor !== null))
  const invalidDate = result.candidates.find((candidate) => candidate.field_path === 'document.legal_date.hearing')
  assert.equal(invalidDate?.validation_state, 'invalid')
  assert.deepEqual(invalidDate?.validation_error_codes, ['invalid_calendar_date'])
})

test('structured semantic keys are stable across reordered arrays and do not use indexes', () => {
  const first = provenanceMaterializationFromAnalysis(analysis, 2, pages)
  const reordered = aiDocumentPayloadSchema.parse({ ...providerPayload,
    client_identifiers_observed: [...providerPayload.client_identifiers_observed].reverse(),
    legal_dates: [...providerPayload.legal_dates].reverse() })
  const second = provenanceMaterializationFromAnalysis(reordered, 2, pages)
  const relevant = (result: typeof first) => result.candidates.filter((candidate) => candidate.field_path.startsWith('document.client_identifier.') || candidate.field_path.startsWith('document.legal_date.'))
    .map((candidate) => candidate.semantic_candidate_key).sort()
  assert.deepEqual(relevant(first), relevant(second))
  assert.ok(relevant(first).every((key) => !/:\d+$/.test(key)))
})

test('money/provision/party candidates are provisional and source verified without identity or relationship effects', () => {
  const result = provenanceMaterializationFromAnalysis(analysis, 2, pages)
  const tierB = result.candidates.filter((candidate) => ['document.money.tax', 'document.legal_provision.section', 'document.party.taxpayer'].includes(candidate.field_path))
  assert.deepEqual(tierB.map((candidate) => candidate.validation_state), ['provisional', 'provisional', 'provisional'])
  assert.ok(tierB.every((candidate) => candidate.verified_source_anchor !== null))
  assert.equal(result.candidates.some((candidate) => candidate.field_path === 'document.referenced_document_number'), false)
})

test('unsupported normalized actor authority fields fail closed at their own candidate', () => {
  const forged = aiDocumentPayloadSchema.parse({ ...providerPayload, actors: [{
    ...providerPayload.actors[0], source_quote: 'Deputy Commissioner', authority: 'Invented Authority', office: null, jurisdiction: null,
  }] })
  const result = provenanceMaterializationFromAnalysis(forged, 2, pages)
  const issuer = result.candidates.find((candidate) => candidate.field_path === 'document.actor.issuer')
  assert.equal(issuer?.validation_state, 'invalid')
  assert.deepEqual(issuer?.validation_error_codes, ['unsupported_actor_normalization'])
})

test('missing or out-of-bound canonical source fails closed per field', () => {
  const missing = provenanceMaterializationFromAnalysis(analysis, 2, pages.slice(0, 1))
  assert.equal(missing.candidates.find((candidate) => candidate.field_path === 'document.money.tax')?.validation_state, 'invalid')
  const unsafe = aiDocumentPayloadSchema.parse({ ...providerPayload,
    parties: [{ ...providerPayload.parties[0], source_page: 3 }] })
  const result = provenanceMaterializationFromAnalysis(unsafe, 2, pages)
  assert.equal(result.terminalReviewRequired, true)
  assert.equal(result.candidates.some((candidate) => candidate.field_path === 'document.party.taxpayer'), false)
})
