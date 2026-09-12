import assert from 'node:assert/strict'
import test from 'node:test'
import { Type } from '@google/genai'
import {
  actorSemanticKey, aiDocumentPayloadSchema, aiWikiPayloadSchema, clientIdentifierSemanticKey,
  documentResponseSchema, legalDateSemanticKey, legalProvisionSemanticKey, moneyObservationSemanticKey, officialReferenceSemanticKey,
} from './schemas'

const observation = (raw: string, extras: Record<string, unknown> = {}) => ({
  raw, display: raw, precision: 'exact', source_page: 1, source_quote: raw, confidence: 0.96, ...extras,
})
const segment = (kind: 'month' | 'quarter' | 'date_range' | 'financial_year', values: Record<string, string> = {}) => ({
  kind, month: null, quarter: null, financial_year: null, start_date: null, end_date: null, ...values,
})
const period = (kind: string, precision: string, segments: unknown[], raw = 'FY 2023-24', printed = ['2023-24']) => ({
  kind, raw, display: raw, precision, segments, printed_financial_years: printed,
  source_page: 1, source_quote: `Tax period ${raw}`, confidence: 0.96,
})
const officialReference = { role: 'self_identifier', kind: 'notice_reference', completeness: 'complete', namespace: 'cbic.gst',
  raw: 'SCN / 2024 / 001', display: 'SCN/2024/001', components: [{ name: 'serial', value: '001' }],
  source_page: 1, source_quote: 'SCN / 2024 / 001', confidence: 0.99 }
const validDocumentPayload = {
  doc_type: 'SCN', document_title: 'Show Cause Notice', document_class: 'proceeding', document_category: null,
  client_identifiers_observed: [
    observation('27AAPFU0939F1ZV', { kind: 'gstin', catalogue_kind: null }),
    observation('AAPFU0939F', { kind: 'pan', catalogue_kind: null }),
  ],
  client_name: 'Example Private Limited',
  legal_dates: [observation('01.04.2024', { meaning: 'issue', normalized_date: '2024-04-01' })],
  actors: [
    observation('Deputy Commissioner', { actor_kind: 'issuer', procedural_role: 'authority', authority: 'GST Department', office: 'Division I', jurisdiction: 'Mumbai' }),
    observation('Example Private Limited', { actor_kind: 'recipient', procedural_role: 'taxpayer', authority: null, office: null, jurisdiction: null }),
  ],
  tax_periods: [period('financial_year', 'financial_year', [segment('financial_year', { financial_year: '2023-24' })])],
  official_references: [officialReference],
  money_observations: [observation('₹ 900719925474099312345.67', { representation: 'decimal', amount: '900719925474099312345.67', currency: 'INR', component: 'tax', applicable_period_reference: 'FY 2023-24', legal_posture: 'alleged' })],
  parties: [observation('Example Private Limited', { procedural_role: 'taxpayer' })],
  legal_provisions: [observation('Section 73 of the CGST Act', { act_kind: 'cgst_act', act: 'Central Goods and Services Tax Act, 2017', provision_kind: 'section', provision_value: '73' })],
  summary: 'The department alleges short payment of tax and asks the taxpayer to respond.',
  evidence: [], confidence: 0.94,
}

test('canonical extraction derives compatibility fields without accepting legacy provider fields', () => {
  const result = aiDocumentPayloadSchema.parse(validDocumentPayload)
  assert.equal(result.gstin, '27AAPFU0939F1ZV')
  assert.deepEqual(result.client_identifiers, ['27AAPFU0939F1ZV', 'AAPFU0939F'])
  assert.equal(result.doc_date, '2024-04-01')
  assert.equal(result.direction, 'incoming')
  assert.equal(result.issued_by, 'Deputy Commissioner')
  assert.equal(result.reference_number, 'SCN/2024/001')
  assert.equal(result.extracted_amounts.tax, '900719925474099312345.67')
  assert.deepEqual(result.parties_named, ['Example Private Limited'])
  for (const legacy of ['gstin', 'client_identifiers', 'doc_date', 'direction', 'issued_by', 'deadlines', 'extracted_amounts', 'parties_named', 'legal_references']) {
    assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload, [legacy]: null }).success, false)
    assert.equal(documentResponseSchema.properties?.[legacy], undefined)
  }
})

test('client identifier syntax/checksum failures remain isolated auditable observations', () => {
  const identifiers = [
    observation('27AAPFU0939F1ZV', { kind: 'gstin', catalogue_kind: null }),
    observation('27AAPFU0939F1ZU', { kind: 'gstin', catalogue_kind: null }),
    observation('ABCDE1234F', { kind: 'pan', catalogue_kind: null }),
    observation('ABCDE12345', { kind: 'pan', catalogue_kind: null }),
    observation('ABCD12345E', { kind: 'tan', catalogue_kind: null }),
    observation('ABC12345E', { kind: 'tan', catalogue_kind: null }),
    observation('L17110MH1973PLC019786', { kind: 'cin', catalogue_kind: null }),
    observation('L17110MH1973PLC01978X', { kind: 'cin', catalogue_kind: null }),
  ]
  const parsed = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, client_identifiers_observed: identifiers })
  assert.equal(parsed.client_identifiers_observed[0].normalization_state, 'valid')
  assert.equal(parsed.client_identifiers_observed[1].normalization_state, 'invalid')
  assert.equal(parsed.client_identifiers_observed[1].normalized_value, null)
  assert.deepEqual(parsed.client_identifiers_observed.map((item) => item.normalization_state), ['valid', 'invalid', 'valid', 'invalid', 'valid', 'invalid', 'valid', 'invalid'])
  assert.deepEqual(parsed.client_identifiers, ['27AAPFU0939F1ZV', 'ABCDE1234F', 'ABCD12345E', 'L17110MH1973PLC019786'])
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    client_identifiers_observed: [observation('ABC', { kind: 'other_catalogued', catalogue_kind: null })] }).success, false)
})

test('legal dates retain meanings and invalid calendar values without deriving relative dates', () => {
  const dates = [
    observation('31 January 2025', { meaning: 'issue', normalized_date: '2025-01-31' }),
    observation('filed 2 February 2025', { meaning: 'filing', normalized_date: '2025-02-02' }),
    observation('reply within thirty days', { meaning: 'due', normalized_date: null, precision: 'unclear' }),
    observation('31 February 2025', { meaning: 'hearing', normalized_date: '2025-02-31' }),
  ]
  const parsed = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, legal_dates: dates })
  assert.equal(parsed.doc_date, '2025-01-31')
  assert.deepEqual(parsed.legal_dates.map((date) => date.normalization_state), ['valid', 'valid', 'provisional', 'invalid'])
  assert.equal(parsed.legal_dates[3].normalized_date, null)
  assert.deepEqual(parsed.deadlines, [])
})

test('direction is derived only from actor roles and fails closed for unknown/conflict', () => {
  const parsed = aiDocumentPayloadSchema.parse(validDocumentPayload)
  assert.equal(parsed.direction, 'incoming')
  assert.equal(actorSemanticKey(parsed.actors[0]), actorSemanticKey(aiDocumentPayloadSchema.parse({ ...validDocumentPayload,
    actors: [{ ...validDocumentPayload.actors[0], display: 'DC' }, validDocumentPayload.actors[1]] }).actors[0]))
  const outgoing = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, actors: [
    observation('Taxpayer', { actor_kind: 'issuer', procedural_role: 'taxpayer', authority: null, office: null, jurisdiction: null }),
    observation('Commissioner', { actor_kind: 'recipient', procedural_role: 'authority', authority: 'GST Department', office: null, jurisdiction: null }),
  ] })
  assert.equal(outgoing.direction, 'outgoing')
  assert.equal(aiDocumentPayloadSchema.parse({ ...validDocumentPayload, actors: [{ ...validDocumentPayload.actors[0], procedural_role: 'unknown' }] }).direction, null)
  assert.equal(aiDocumentPayloadSchema.parse({ ...validDocumentPayload, actors: [...validDocumentPayload.actors,
    { ...validDocumentPayload.actors[0], raw: 'Taxpayer signatory', procedural_role: 'taxpayer' }] }).direction, null)
})

test('money is lossless, never a JSON number, and duplicate components do not invent a legacy total', () => {
  const huge = validDocumentPayload.money_observations[0]
  const duplicate = { ...huge, raw: '₹ 2.00', display: '₹ 2.00', source_quote: '₹ 2.00', amount: '2.00' }
  const parsed = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, money_observations: [huge, duplicate] })
  assert.equal(parsed.money_observations[0].normalized?.value, '900719925474099312345.67')
  assert.equal(parsed.extracted_amounts.tax, null)
  assert.equal(parsed.extracted_amounts.total_demand, null)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    money_observations: [{ ...huge, amount: 9007199254740992 }] }).success, false)
  const paise = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, money_observations: [
    observation('900719925474099312345 paise', { representation: 'integer_paise', amount: '900719925474099312345', currency: 'INR', component: 'amount_in_dispute', applicable_period_reference: null, legal_posture: 'disputed' }),
  ] })
  assert.equal(paise.money_observations[0].normalized?.value, '900719925474099312345')
  assert.equal(paise.extracted_amounts.amount_in_dispute, '900719925474099312345')
  assert.equal(documentResponseSchema.properties?.money_observations.items?.properties?.amount.type, Type.STRING)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    money_observations: [{ ...huge, invented_total: '1' }] }).success, false)
})

test('provision normalization preserves raw evidence and stays separate from official references', () => {
  const parsed = aiDocumentPayloadSchema.parse(validDocumentPayload)
  assert.equal(parsed.legal_provisions[0].raw, 'Section 73 of the CGST Act')
  assert.equal(parsed.legal_provisions[0].normalized?.value, '73')
  assert.deepEqual(parsed.legal_provisions[0].normalized?.components, ['73'])
  assert.equal(parsed.official_references.length, 1)
})

test('unknown party roles remain provisional without rewriting proper names', () => {
  const parsed = aiDocumentPayloadSchema.parse({ ...validDocumentPayload,
    parties: [observation('श्री राम ट्रेडर्स', { display: 'Shri Ram Traders', procedural_role: 'unknown' })] })
  assert.equal(parsed.parties[0].raw, 'श्री राम ट्रेडर्स')
  assert.equal(parsed.parties[0].display, 'Shri Ram Traders')
  assert.equal(parsed.parties[0].normalization_state, 'provisional')
})

test('semantic keys are bounded, stable, content-derived, and role-separated', () => {
  const parsed = aiDocumentPayloadSchema.parse(validDocumentPayload)
  const keys = [clientIdentifierSemanticKey(parsed.client_identifiers_observed[0]), legalDateSemanticKey(parsed.legal_dates[0]),
    moneyObservationSemanticKey(parsed.money_observations[0]), officialReferenceSemanticKey(parsed.official_references[0])]
  assert.ok(keys.every((key) => /^[a-z_]+(?::[a-z_]+)?:[0-9a-f]{32}$/.test(key)))
  assert.equal(moneyObservationSemanticKey(parsed.money_observations[0]), moneyObservationSemanticKey(aiDocumentPayloadSchema.parse({ ...validDocumentPayload,
    money_observations: [{ ...validDocumentPayload.money_observations[0], display: 'Tax amount' }] }).money_observations[0]))

  const actorWithDifferentOffice = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, actors: [
    { ...validDocumentPayload.actors[0], office: 'Division II' }, validDocumentPayload.actors[1],
  ] }).actors[0]
  const formattingEquivalentActor = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, actors: [
    { ...validDocumentPayload.actors[0], authority: 'ＧＳＴ   department' }, validDocumentPayload.actors[1],
  ] }).actors[0]
  assert.notEqual(actorSemanticKey(parsed.actors[0]), actorSemanticKey(actorWithDifferentOffice))
  assert.equal(actorSemanticKey(parsed.actors[0]), actorSemanticKey(formattingEquivalentActor))

  const provisionA = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, legal_provisions: [
    { ...validDocumentPayload.legal_provisions[0], act_kind: 'other_catalogued', act: 'Custom Act A' },
  ] }).legal_provisions[0]
  const provisionB = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, legal_provisions: [
    { ...validDocumentPayload.legal_provisions[0], act_kind: 'other_catalogued', act: 'Custom Act B' },
  ] }).legal_provisions[0]
  const formattingEquivalentProvision = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, legal_provisions: [
    { ...validDocumentPayload.legal_provisions[0], act_kind: 'other_catalogued', act: 'Ｃｕｓｔｏｍ   act A' },
  ] }).legal_provisions[0]
  assert.notEqual(legalProvisionSemanticKey(provisionA), legalProvisionSemanticKey(provisionB))
  assert.equal(legalProvisionSemanticKey(provisionA), legalProvisionSemanticKey(formattingEquivalentProvision))
})

test('typed periods retain precision and provider schema remains recursively derived and strict', () => {
  const periods = [
    period('month', 'month', [segment('month', { month: '2020-01' })], 'JAN 2020 – JAN 2020', []),
    period('quarter', 'quarter', [segment('quarter', { quarter: 'Q2', financial_year: '2021-22' })], 'Q2 FY 2021-22', ['2021-22']),
    period('exact_date_range', 'exact_date', [segment('date_range', { start_date: '2022-03-15', end_date: '2022-04-10' })], '15.03.2022 to 10.04.2022', []),
    period('multi_financial_year', 'financial_year', [segment('financial_year', { financial_year: '2019-20' }), segment('financial_year', { financial_year: '2021-22' })], 'FY 2019-20 and FY 2021-22', ['2019-20', '2021-22']),
    period('non_contiguous', 'mixed', [segment('month', { month: '2020-01' }), segment('quarter', { quarter: 'Q4', financial_year: '2021-22' })], 'January 2020 and Q4 FY 2021-22', ['2021-22']),
    period('unclear', 'unclear', [], 'relevant period', []),
  ]
  const parsed = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, tax_periods: periods })
  assert.deepEqual(parsed.tax_periods[0].derived_financial_years, ['2019-20'])
  assert.deepEqual(parsed.tax_periods[2].derived_financial_years, ['2021-22', '2022-23'])
  assert.equal(documentResponseSchema.type, Type.OBJECT)
  assert.deepEqual(documentResponseSchema.required, Object.keys(documentResponseSchema.properties!))
  assert.ok(documentResponseSchema.properties?.client_identifiers_observed)
  assert.ok(documentResponseSchema.properties?.money_observations)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload, invented_legal_opinion: 'will win' }).success, false)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload, page_text: [] }).success, false)
})

test('D09-T03 printed/derived conflicts and malformed period shapes remain covered', () => {
  const conflict = aiDocumentPayloadSchema.parse({ ...validDocumentPayload,
    tax_periods: [period('month', 'month', [segment('month', { month: '2020-01' })], 'January 2020', ['2020-21'])] })
  assert.equal(conflict.tax_periods[0].conflict, true)
  assert.deepEqual(conflict.tax_periods[0].derived_financial_years, ['2019-20'])
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    tax_periods: [period('month', 'month', [segment('month', { month: '2020-01', start_date: '2020-01-01' })])] }).success, false)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    tax_periods: [period('financial_year', 'financial_year', [segment('financial_year', { financial_year: '2023-99' })], 'FY 2023-99', ['2023-99'])] }).success, false)
})

test('D09-T03 official references remain canonical, role-separated, and non-matchable when incomplete', () => {
  const parsed = aiDocumentPayloadSchema.parse({ ...validDocumentPayload, official_references: [
    { ...officialReference, namespace: ' cbic . gst ', raw: 'SCN / 001 / 2026', display: 'SCN/001/2026', components: [{ name: 'year', value: '9999' }] },
    { ...officialReference, role: 'outbound_mention', completeness: 'partial', namespace: null },
    { ...officialReference, role: 'outbound_mention', kind: 'other_official_reference' },
  ] })
  assert.equal(parsed.official_references[0].namespace_normalized, 'CBIC.GST')
  assert.equal(parsed.official_references[0].normalized_value, 'SCN/001/2026')
  assert.deepEqual(parsed.official_references[0].components, { kind: 'notice_reference', segments: ['SCN', '001', '2026'], prefix: 'SCN', numericCore: '001', year: '2026' })
  assert.deepEqual(parsed.official_references.map((reference) => reference.match_eligible), [true, false, false])
  assert.notEqual(officialReferenceSemanticKey(parsed.official_references[0]), officialReferenceSemanticKey(parsed.official_references[1]))
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    official_references: [{ ...officialReference, role: 'parent' }] }).success, false)
})

test('control characters are rejected before source observations are normalized', () => {
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    parties: [observation('Bad\nName', { procedural_role: 'unknown' })] }).success, false)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    legal_dates: [observation('1 Jan 2025', { meaning: 'issue', normalized_date: '2025-01-01', source_quote: 'bad\nquote' })] }).success, false)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    official_references: [{ ...officialReference, raw: 'SCN\n001' }] }).success, false)
  assert.equal(aiDocumentPayloadSchema.safeParse({ ...validDocumentPayload,
    tax_periods: [{ ...period('month', 'month', [segment('month', { month: '2020-01' })], 'JAN 2020', []), source_quote: 'JAN\n2020' }] }).success, false)
})

test('validates the current Case Brief storage contract', () => {
  assert.equal(aiWikiPayloadSchema.safeParse({ executive_summary: 'Summary.', key_arguments: 'Arguments.', outstanding_tasks: 'Tasks.' }).success, true)
})
