import { Type, type Schema } from '@google/genai'
import { createHash } from 'node:crypto'
import { z } from 'zod'
import { vertexSchemaFromZod } from './vertex-schema-adapter'

export const DOCUMENT_TYPES = [
  'DRC-01', 'DRC-01A', 'DRC-01C', 'DRC-03', 'DRC-07', 'SCN', 'OIO', 'OIA',
  'APL-01', 'APL-02', 'APL-05', 'STAY', 'REPLY', 'HC_PETITION', 'HC_ORDER',
  'SC_PETITION', 'SC_ORDER', 'OTHER',
] as const
export const EXTRACTION_SCHEMA_VERSION = 'document-extraction-v4'
export const EXTRACTION_CATALOGUE_VERSION = 'gst-legal-material-observation-catalogue-v3'
export const EXTRACTION_NORMALIZER_VERSION = 'typed-material-observation-normalizer-v3'
export const OFFICIAL_REFERENCE_KINDS = [
  'proceeding_case_id', 'notice_reference', 'order_reference', 'appeal_reference',
  'court_case_number', 'other_official_reference',
] as const

const containsControlCharacter = (value: string) => /[\p{Cc}]/u.test(value)
const sourceText = (max: number, min = 1) => z.string().min(min).max(max)
  .refine((value) => !containsControlCharacter(value), 'control characters are not allowed')
  .refine((value) => value.trim().length >= min, 'source text is empty after trimming')
  .transform((value) => value.trim())
const nullableText = sourceText(1024).nullable()
const isoDate = z.string().regex(/^[1-9]\d{3}-\d{2}-\d{2}$/).superRefine((value, context) => {
  const date = new Date(`${value}T00:00:00Z`)
  if (Number.isNaN(date.valueOf()) || date.toISOString().slice(0, 10) !== value) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'date is not a real calendar date' })
  }
})
const nullableDate = isoDate.nullable()
const financialYear = z.string().regex(/^\d{4}-\d{2}$/).superRefine((value, context) => {
  if (Number(value.slice(5)) !== (Number(value.slice(0, 4)) + 1) % 100) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'financial year suffix is not consecutive' })
  }
})
const confidence = z.number().min(0).max(1)

const evidenceSchema = z.object({
  field: z.enum(['document_type', 'client_name']),
  value: sourceText(1024), page_number: z.number().int().positive().nullable(),
  quote: nullableText, confidence,
}).strict()

const periodSegmentSchema = z.object({
  kind: z.enum(['month', 'quarter', 'date_range', 'financial_year']),
  month: z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/).nullable(),
  quarter: z.enum(['Q1', 'Q2', 'Q3', 'Q4']).nullable(), financial_year: financialYear.nullable(),
  start_date: nullableDate, end_date: nullableDate,
}).strict().superRefine((segment, context) => {
  const expected: Record<typeof segment.kind, string[]> = {
    month: ['month'], quarter: ['quarter', 'financial_year'], date_range: ['start_date', 'end_date'], financial_year: ['financial_year'],
  }
  const keys = ['month', 'quarter', 'financial_year', 'start_date', 'end_date'] as const
  if (keys.some((key) => (segment[key] !== null) !== expected[segment.kind].includes(key))) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'period segment fields do not match its kind' })
  }
  if (segment.kind === 'date_range' && segment.start_date! > segment.end_date!) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'period date range is reversed' })
  }
  if (segment.kind === 'date_range') {
    const first = Number(segment.start_date!.slice(0, 4)) - (Number(segment.start_date!.slice(5, 7)) < 4 ? 1 : 0)
    const last = Number(segment.end_date!.slice(0, 4)) - (Number(segment.end_date!.slice(5, 7)) < 4 ? 1 : 0)
    if (last - first >= 30) context.addIssue({ code: z.ZodIssueCode.custom, message: 'period spans too many financial years' })
  }
})

export const taxPeriodInputSchema = z.object({
  kind: z.enum(['month', 'quarter', 'exact_date_range', 'financial_year', 'multi_financial_year', 'non_contiguous', 'unclear']),
  raw: sourceText(512), display: sourceText(512),
  precision: z.enum(['month', 'quarter', 'exact_date', 'financial_year', 'mixed', 'unclear']),
  segments: z.array(periodSegmentSchema).max(24), printed_financial_years: z.array(financialYear).max(30),
  source_page: z.number().int().positive(), source_quote: sourceText(1000), confidence,
}).strict().superRefine((period, context) => {
  const kinds = period.segments.map((segment) => segment.kind)
  const valid = period.kind === 'unclear' ? period.segments.length === 0 && period.precision === 'unclear'
    : period.kind === 'month' ? period.segments.length === 1 && kinds[0] === 'month' && period.precision === 'month'
    : period.kind === 'quarter' ? period.segments.length === 1 && kinds[0] === 'quarter' && period.precision === 'quarter'
    : period.kind === 'exact_date_range' ? period.segments.length === 1 && kinds[0] === 'date_range' && period.precision === 'exact_date'
    : period.kind === 'financial_year' ? period.segments.length === 1 && kinds[0] === 'financial_year' && period.precision === 'financial_year'
    : period.kind === 'multi_financial_year' ? period.segments.length >= 2 && kinds.every((kind) => kind === 'financial_year') && period.precision === 'financial_year'
    : period.segments.length >= 2 && period.precision === 'mixed'
  if (!valid) context.addIssue({ code: z.ZodIssueCode.custom, message: 'period shape and precision do not agree' })
})

function fyForMonth(month: string) {
  const [year, monthNumber] = month.split('-').map(Number)
  const start = monthNumber >= 4 ? year : year - 1
  return `${start}-${String(start + 1).slice(-2)}`
}
function financialYearsForRange(startDate: string, endDate: string) {
  const start = Number(startDate.slice(0, 4)) - (Number(startDate.slice(5, 7)) < 4 ? 1 : 0)
  const end = Number(endDate.slice(0, 4)) - (Number(endDate.slice(5, 7)) < 4 ? 1 : 0)
  return Array.from({ length: end - start + 1 }, (_, index) => `${start + index}-${String(start + index + 1).slice(-2)}`)
}
export function normalizeTaxPeriod(period: z.infer<typeof taxPeriodInputSchema>) {
  const derived: string[] = []
  for (const segment of period.segments) {
    const values = segment.kind === 'month' ? [fyForMonth(segment.month!)]
      : segment.kind === 'date_range' ? financialYearsForRange(segment.start_date!, segment.end_date!)
      : segment.financial_year ? [segment.financial_year] : []
    for (const value of values) if (!derived.includes(value)) derived.push(value)
  }
  const printed = [...new Set(period.printed_financial_years)]
  const canonicalPrinted = [...printed].sort()
  const canonicalDerived = [...derived].sort()
  return { ...period, financial_years: derived, printed_financial_years: printed, derived_financial_years: derived,
    conflict: printed.length > 0 && (canonicalPrinted.length !== canonicalDerived.length
      || canonicalPrinted.some((value, index) => value !== canonicalDerived[index])),
    catalogue_version: EXTRACTION_CATALOGUE_VERSION, normalizer_version: EXTRACTION_NORMALIZER_VERSION }
}
const taxPeriodSchema = taxPeriodInputSchema.transform(normalizeTaxPeriod)

const officialReferenceComponentSchema = z.object({
  name: z.string().regex(/^[a-z][a-z0-9_]{0,63}$/), value: z.string().trim().min(1).max(128),
}).strict()
export const officialReferenceInputSchema = z.object({
  role: z.enum(['self_identifier', 'outbound_mention']), kind: z.enum(OFFICIAL_REFERENCE_KINDS),
  completeness: z.enum(['complete', 'partial', 'unknown']),
  namespace: sourceText(160, 2).nullable(),
  raw: sourceText(300), display: sourceText(300),
  components: z.array(officialReferenceComponentSchema).max(16), source_page: z.number().int().positive(),
  source_quote: sourceText(1000), confidence,
}).strict().superRefine((reference, context) => {
  if (!/[\p{L}\p{N}]/u.test(reference.raw)) context.addIssue({ code: z.ZodIssueCode.custom, message: 'official reference has no identifier characters' })
})

function normalizeMatterIdentifierNamespaceV1(namespace: string | null) {
  if (namespace === null || namespace.length < 2 || namespace.length > 160 || /[\u0000-\u001f\u007f]/.test(namespace)) return null
  const value = namespace.normalize('NFKC').toUpperCase().replace(/\s+/gu, ' ').trim()
    .replace(/\s*([/.:_-])\s*/gu, '$1')
  return value.length >= 2 && value.length <= 160 && /[\p{L}\p{N}]/u.test(value) ? value : null
}

function normalizeMatterIdentifierValueV1(kind: typeof OFFICIAL_REFERENCE_KINDS[number], raw: string) {
  if (raw.length < 1 || raw.length > 300 || /[\u0000-\u001f\u007f]/.test(raw)) return null
  const normalizedValue = raw.normalize('NFKC').toUpperCase().replace(/[‐‑‒–—−]/gu, '-').replace(/\s+/gu, ' ').trim()
    .replace(/\s*([/.:_-])\s*/gu, '$1')
  if (normalizedValue.length < 1 || normalizedValue.length > 300 || !/[\p{L}\p{N}]/u.test(normalizedValue)) return null
  const segments = normalizedValue.split(/[/.:_-]+/u)
  let prefix: string | undefined
  let numericCore: string | undefined
  let year: string | undefined
  for (const segment of segments) {
    if (prefix === undefined && /^[\p{L} ]{1,80}$/u.test(segment)) prefix = segment
    if (numericCore === undefined && /^\d{1,40}$/u.test(segment)) numericCore = segment
    if (/^(19|20)\d{2}$/u.test(segment)) year = segment
  }
  return { normalizedValue, components: { kind, segments, ...(prefix === undefined ? {} : { prefix }),
    ...(numericCore === undefined ? {} : { numericCore }), ...(year === undefined ? {} : { year }) } }
}

const UNKNOWN_NAMESPACES = new Set(['UNKNOWN', 'UNCLEAR', 'N/A', 'NA', 'NOT AVAILABLE', 'UNSPECIFIED'])
export function normalizeOfficialReference(reference: z.infer<typeof officialReferenceInputSchema>) {
  const namespaceNormalized = normalizeMatterIdentifierNamespaceV1(reference.namespace)
  const value = normalizeMatterIdentifierValueV1(reference.kind, reference.raw)
  const matchEligible = reference.completeness === 'complete' && reference.kind !== 'other_official_reference'
    && namespaceNormalized !== null && !UNKNOWN_NAMESPACES.has(namespaceNormalized) && value !== null
  return { ...reference, namespace_normalized: namespaceNormalized, normalized_value: value?.normalizedValue ?? null,
    components: value?.components ?? { kind: reference.kind, segments: [] }, match_eligible: matchEligible,
    catalogue_version: EXTRACTION_CATALOGUE_VERSION, normalizer_version: EXTRACTION_NORMALIZER_VERSION }
}
export function officialReferenceSemanticKey(reference: ReturnType<typeof normalizeOfficialReference>) {
  const material = JSON.stringify([reference.role, reference.namespace_normalized, reference.kind, reference.normalized_value])
  return `official_reference:${reference.role}:${createHash('sha256').update(material).digest('hex').slice(0, 32)}`
}
const officialReferenceSchema = officialReferenceInputSchema.transform(normalizeOfficialReference)

const OBSERVATION_PRECISIONS = ['exact', 'partial', 'unclear'] as const
const observationSourceShape = {
  raw: sourceText(512), display: sourceText(512), precision: z.enum(OBSERVATION_PRECISIONS),
  source_page: z.number().int().positive(), source_quote: sourceText(1000), confidence,
}
const withVersions = <T extends object>(observation: T) => ({ ...observation,
  catalogue_version: EXTRACTION_CATALOGUE_VERSION, normalizer_version: EXTRACTION_NORMALIZER_VERSION })
const stableObservationKey = (family: string, material: unknown) =>
  `${family}:${createHash('sha256').update(JSON.stringify(material)).digest('hex').slice(0, 32)}`
const canonicalEntityComponent = (value: string | null) => value === null ? null
  : value.normalize('NFKC').toUpperCase().replace(/\s+/gu, ' ').trim()
const normalizedIdentifierText = (value: string) => value.normalize('NFKC').toUpperCase().replace(/[\s./,_-]/gu, '')
const GSTIN_ALPHABET = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'

export function gstinChecksumValid(value: string) {
  if (!/^\d{2}[A-Z]{5}\d{4}[A-Z][0-9A-Z]Z[0-9A-Z]$/.test(value)) return false
  let total = 0
  for (let index = 0; index < 14; index += 1) {
    const product = GSTIN_ALPHABET.indexOf(value[index]) * (index % 2 === 0 ? 1 : 2)
    total += Math.floor(product / 36) + (product % 36)
  }
  return GSTIN_ALPHABET[(36 - total % 36) % 36] === value[14]
}

const CLIENT_IDENTIFIER_KINDS = ['gstin', 'pan', 'tan', 'cin', 'other_catalogued'] as const
const OTHER_CLIENT_IDENTIFIER_KINDS = ['iec', 'udyam_registration', 'professional_tax_registration', 'other_registration'] as const
export const clientIdentifierInputSchema = z.object({
  kind: z.enum(CLIENT_IDENTIFIER_KINDS), catalogue_kind: z.enum(OTHER_CLIENT_IDENTIFIER_KINDS).nullable(),
  ...observationSourceShape,
}).strict().superRefine((identifier, context) => {
  if ((identifier.kind === 'other_catalogued') !== (identifier.catalogue_kind !== null)) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'catalogue kind must identify only other_catalogued identifiers' })
  }
})
export function normalizeClientIdentifier(identifier: z.infer<typeof clientIdentifierInputSchema>) {
  const candidate = normalizedIdentifierText(identifier.raw)
  const syntaxValid = identifier.kind === 'gstin' ? gstinChecksumValid(candidate)
    : identifier.kind === 'pan' ? /^[A-Z]{5}\d{4}[A-Z]$/.test(candidate)
    : identifier.kind === 'tan' ? /^[A-Z]{4}\d{5}[A-Z]$/.test(candidate)
    : identifier.kind === 'cin' ? /^[LU]\d{5}[A-Z]{2}\d{4}[A-Z]{3}\d{6}$/.test(candidate)
    : candidate.length >= 2 && candidate.length <= 128 && /^[A-Z0-9]+$/.test(candidate)
  const exact = identifier.precision === 'exact'
  return withVersions({ ...identifier, normalized_value: syntaxValid && exact ? candidate : null,
    normalization_state: !syntaxValid ? 'invalid' as const : exact ? 'valid' as const : 'provisional' as const,
    validation_error: !syntaxValid ? `invalid_${identifier.kind}` : exact ? null : 'identifier_not_exact' })
}
export const clientIdentifierSemanticKey = (identifier: ReturnType<typeof normalizeClientIdentifier>) =>
  stableObservationKey('client_identifier', [identifier.kind, identifier.catalogue_kind, identifier.normalized_value ?? normalizedIdentifierText(identifier.raw)])
const clientIdentifierSchema = clientIdentifierInputSchema.transform(normalizeClientIdentifier)

export const legalDateInputSchema = z.object({
  meaning: z.enum(['issue', 'filing', 'communication_service', 'order', 'hearing', 'due', 'source_unknown']),
  normalized_date: sourceText(32).nullable(), ...observationSourceShape,
}).strict()
export function normalizeLegalDate(observation: z.infer<typeof legalDateInputSchema>) {
  const parsed = observation.normalized_date === null ? null : isoDate.safeParse(observation.normalized_date)
  const exact = observation.precision === 'exact'
  const validDate = parsed?.success ? parsed.data : null
  return withVersions({ ...observation, proposed_normalized_date: observation.normalized_date, normalized_date: validDate,
    normalization_state: parsed && !parsed.success ? 'invalid' as const : validDate && exact ? 'valid' as const : 'provisional' as const,
    validation_error: parsed && !parsed.success ? 'invalid_calendar_date' : validDate && exact ? null : 'date_not_exact' })
}
export const legalDateSemanticKey = (date: ReturnType<typeof normalizeLegalDate>) =>
  stableObservationKey('legal_date', [date.meaning, date.normalized_date ?? date.raw.normalize('NFKC').toUpperCase()])
const legalDateSchema = legalDateInputSchema.transform(normalizeLegalDate)

const ACTOR_ROLES = ['authority', 'department', 'court', 'tribunal', 'taxpayer', 'appellant', 'respondent', 'petitioner', 'applicant', 'other', 'unknown'] as const
export const actorInputSchema = z.object({
  actor_kind: z.enum(['issuer', 'recipient']), procedural_role: z.enum(ACTOR_ROLES),
  authority: nullableText, office: nullableText, jurisdiction: nullableText, ...observationSourceShape,
}).strict()
export function normalizeActor(actor: z.infer<typeof actorInputSchema>) {
  return withVersions({ ...actor, normalized: { procedural_role: actor.procedural_role,
    authority: actor.authority, office: actor.office, jurisdiction: actor.jurisdiction },
    normalization_state: actor.procedural_role === 'unknown' || actor.precision !== 'exact' ? 'provisional' as const : 'valid' as const,
    validation_error: actor.procedural_role === 'unknown' ? 'unknown_actor_role' : actor.precision !== 'exact' ? 'actor_not_exact' : null })
}
export const actorSemanticKey = (actor: ReturnType<typeof normalizeActor>) =>
  stableObservationKey('actor', [actor.actor_kind, actor.procedural_role, canonicalEntityComponent(actor.raw),
    canonicalEntityComponent(actor.authority), canonicalEntityComponent(actor.office), canonicalEntityComponent(actor.jurisdiction)])
const actorSchema = actorInputSchema.transform(normalizeActor)

const PARTY_ROLES = ['taxpayer', 'appellant', 'respondent', 'petitioner', 'applicant', 'authority', 'department', 'court', 'tribunal', 'intervenor', 'other', 'unknown'] as const
export const partyInputSchema = z.object({ procedural_role: z.enum(PARTY_ROLES), ...observationSourceShape }).strict()
export function normalizeParty(party: z.infer<typeof partyInputSchema>) {
  return withVersions({ ...party, normalized: { name: party.display, procedural_role: party.procedural_role },
    normalization_state: party.procedural_role === 'unknown' || party.precision !== 'exact' ? 'provisional' as const : 'valid' as const,
    validation_error: party.procedural_role === 'unknown' ? 'unknown_party_role' : party.precision !== 'exact' ? 'party_not_exact' : null })
}
export const partySemanticKey = (party: ReturnType<typeof normalizeParty>) =>
  stableObservationKey('party', [party.procedural_role, party.raw.normalize('NFKC').toUpperCase()])
const partySchema = partyInputSchema.transform(normalizeParty)

const MONEY_COMPONENTS = ['tax', 'interest', 'penalty', 'fee', 'pre_deposit', 'total_demand', 'amount_in_dispute', 'amount_relief', 'other'] as const
const MONEY_POSTURES = ['alleged', 'demanded', 'confirmed', 'paid', 'refunded', 'disputed', 'relief', 'other', 'unknown'] as const
export const moneyObservationInputSchema = z.object({
  representation: z.enum(['decimal', 'integer_paise']), amount: sourceText(256), currency: z.string().regex(/^[A-Z]{3}$/),
  component: z.enum(MONEY_COMPONENTS), applicable_period_reference: sourceText(512).nullable(),
  legal_posture: z.enum(MONEY_POSTURES), ...observationSourceShape,
}).strict()
const DECIMAL_AMOUNT = /^(0|[1-9]\d*)(\.\d{1,6})?$/
const PAISE_AMOUNT = /^(0|[1-9]\d*)$/
export function normalizeMoneyObservation(money: z.infer<typeof moneyObservationInputSchema>) {
  const amountValid = (money.representation === 'decimal' ? DECIMAL_AMOUNT : PAISE_AMOUNT).test(money.amount)
    && money.amount.length <= 128
  return withVersions({ ...money, normalized: amountValid ? { representation: money.representation, value: money.amount,
    currency: money.currency, component: money.component, applicable_period_reference: money.applicable_period_reference,
    legal_posture: money.legal_posture } : null,
    normalization_state: !amountValid ? 'invalid' as const : money.precision === 'exact' ? 'valid' as const : 'provisional' as const,
    validation_error: !amountValid ? 'invalid_money_string' : money.precision === 'exact' ? null : 'money_not_exact' })
}
export const moneyObservationSemanticKey = (money: ReturnType<typeof normalizeMoneyObservation>) =>
  stableObservationKey('money', [money.component, money.currency, money.representation, money.amount, money.applicable_period_reference, money.legal_posture])
const moneyObservationSchema = moneyObservationInputSchema.transform(normalizeMoneyObservation)

const ACT_KINDS = ['cgst_act', 'igst_act', 'gst_rules', 'constitution', 'other_catalogued', 'uncatalogued'] as const
const PROVISION_KINDS = ['section', 'rule', 'article', 'notification', 'circular', 'instruction', 'other'] as const
export const legalProvisionInputSchema = z.object({
  act_kind: z.enum(ACT_KINDS), act: nullableText, provision_kind: z.enum(PROVISION_KINDS),
  provision_value: sourceText(256), ...observationSourceShape,
}).strict()
export function normalizeLegalProvision(provision: z.infer<typeof legalProvisionInputSchema>) {
  const normalizedValue = provision.provision_value.normalize('NFKC').toUpperCase().replace(/\s+/gu, ' ').trim()
    .replace(/\s*([/().:_-])\s*/gu, '$1')
  const valid = /[\p{L}\p{N}]/u.test(normalizedValue)
  const components = valid ? normalizedValue.split(/[/().:_-]+/u).filter(Boolean) : []
  return withVersions({ ...provision, normalized: valid ? { act_kind: provision.act_kind, act: provision.act,
    provision_kind: provision.provision_kind, value: normalizedValue, components } : null,
    normalization_state: !valid ? 'invalid' as const : provision.act_kind === 'uncatalogued' || provision.precision !== 'exact' ? 'provisional' as const : 'valid' as const,
    validation_error: !valid ? 'invalid_legal_provision' : provision.act_kind === 'uncatalogued' ? 'uncatalogued_act' : provision.precision !== 'exact' ? 'provision_not_exact' : null })
}
export const legalProvisionSemanticKey = (provision: ReturnType<typeof normalizeLegalProvision>) =>
  stableObservationKey('legal_provision', [provision.act_kind, canonicalEntityComponent(provision.act), provision.provision_kind,
    provision.normalized?.value ?? canonicalEntityComponent(provision.raw)])
const legalProvisionSchema = legalProvisionInputSchema.transform(normalizeLegalProvision)

type Actor = ReturnType<typeof normalizeActor>
function deriveDirection(actors: Actor[]): 'incoming' | 'outgoing' | null {
  const official = new Set(['authority', 'department', 'court', 'tribunal'])
  const privateParty = new Set(['taxpayer', 'appellant', 'respondent', 'petitioner', 'applicant'])
  const issuerGroups = new Set(actors.filter((actor) => actor.actor_kind === 'issuer').map((actor) =>
    official.has(actor.procedural_role) ? 'official' : privateParty.has(actor.procedural_role) ? 'private' : 'unknown'))
  const recipientGroups = new Set(actors.filter((actor) => actor.actor_kind === 'recipient').map((actor) =>
    official.has(actor.procedural_role) ? 'official' : privateParty.has(actor.procedural_role) ? 'private' : 'unknown'))
  if (issuerGroups.size !== 1 || recipientGroups.size !== 1 || issuerGroups.has('unknown') || recipientGroups.has('unknown')) return null
  if (issuerGroups.has('official') && recipientGroups.has('private')) return 'incoming'
  if (issuerGroups.has('private') && recipientGroups.has('official')) return 'outgoing'
  return null
}

const documentProviderPayloadSchema = z.object({
  doc_type: z.enum(DOCUMENT_TYPES).nullable(), document_title: nullableText,
  document_class: z.enum(['proceeding', 'supporting']),
  document_category: z.enum(['invoice', 'client_document', 'explanation', 'evidence', 'other']).nullable(),
  client_identifiers_observed: z.array(clientIdentifierSchema).max(50), client_name: nullableText,
  legal_dates: z.array(legalDateSchema).max(100), actors: z.array(actorSchema).max(100),
  tax_periods: z.array(taxPeriodSchema).max(30), official_references: z.array(officialReferenceSchema).max(100),
  money_observations: z.array(moneyObservationSchema).max(200), parties: z.array(partySchema).max(100),
  legal_provisions: z.array(legalProvisionSchema).max(100), summary: z.string().trim().min(1).max(6000),
  evidence: z.array(evidenceSchema).max(200), confidence,
}).strict()

export const aiDocumentPayloadSchema = documentProviderPayloadSchema.transform((payload) => {
  const selfReference = payload.official_references.find((reference) => reference.role === 'self_identifier' && reference.match_eligible)
  const financialYears = payload.tax_periods.flatMap((period) => period.financial_years).filter((value, index, all) => all.indexOf(value) === index)
  const clientIdentifiers = payload.client_identifiers_observed.flatMap((identifier) => identifier.normalized_value ? [identifier.normalized_value] : [])
  const gstin = payload.client_identifiers_observed.find((identifier) => identifier.kind === 'gstin' && identifier.normalized_value)?.normalized_value ?? null
  const legalDatePriority = ['issue', 'filing', 'communication_service', 'order', 'hearing', 'due', 'source_unknown']
  const docDate = [...payload.legal_dates].filter((date) => date.normalization_state === 'valid' && date.normalized_date)
    .sort((left, right) => legalDatePriority.indexOf(left.meaning) - legalDatePriority.indexOf(right.meaning))[0]?.normalized_date ?? null
  const direction = deriveDirection(payload.actors)
  const issuedBy = payload.actors.find((actor) => actor.actor_kind === 'issuer')?.display ?? null
  const amountComponents = ['tax', 'interest', 'penalty', 'fee', 'pre_deposit', 'total_demand', 'amount_in_dispute', 'amount_relief'] as const
  const extractedAmounts = Object.fromEntries(amountComponents.map((component) => {
    const values = payload.money_observations.filter((money) => money.component === component && money.normalized !== null)
    return [component, values.length === 1 ? values[0].normalized!.value : null]
  })) as Record<typeof amountComponents[number], string | null>
  const deadlines = payload.legal_dates.filter((date) => date.meaning === 'due' && date.normalization_state === 'valid' && date.normalized_date)
    .map((date) => ({ type: 'other' as const, due_date: date.normalized_date!, description: date.display,
      source_page: date.source_page, source_quote: date.source_quote, confidence: date.confidence }))
  const legalReferences = payload.legal_provisions.map((provision) => ({ act: provision.act,
    provision_type: provision.provision_kind === 'article' ? 'other' as const : provision.provision_kind,
    provision_number: provision.normalized?.value ?? provision.provision_value, context: null,
    page_number: provision.source_page, confidence: provision.confidence }))
  return { ...payload, gstin, client_identifiers: clientIdentifiers, doc_date: docDate, issued_by: issuedBy, direction,
    extracted_amounts: extractedAmounts, parties_named: payload.parties.map((party) => party.display), legal_references: legalReferences,
    deadlines, reference_number: selfReference?.display ?? null, financial_years: financialYears,
    chaining_attributes: { references_documents: payload.official_references.filter((reference) => reference.role === 'outbound_mention' && reference.match_eligible).map((reference) => reference.display),
      gstin, financial_years: financialYears, matter_ref: null, link_type: null } }
})
export type AIDocumentPayload = z.infer<typeof aiDocumentPayloadSchema>
export type AIUsage = { promptTokens: number; candidateTokens: number; totalTokens: number }
export type AIDocumentResult = AIDocumentPayload & { prompt_version: string; usage?: AIUsage }

export const aiWikiPayloadSchema = z.object({ executive_summary: z.string().trim().min(1).max(12000),
  key_arguments: z.string().trim().min(1).max(16000), outstanding_tasks: z.string().trim().min(1).max(12000) }).strict()
export type AIWikiPayload = z.infer<typeof aiWikiPayloadSchema>
export type AIWikiResult = AIWikiPayload & { usage?: AIUsage }

export const documentResponseSchema: Schema = vertexSchemaFromZod(aiDocumentPayloadSchema)
export const wikiResponseSchema: Schema = { type: Type.OBJECT, required: ['executive_summary', 'key_arguments', 'outstanding_tasks'],
  properties: { executive_summary: { type: Type.STRING }, key_arguments: { type: Type.STRING }, outstanding_tasks: { type: Type.STRING } } }
