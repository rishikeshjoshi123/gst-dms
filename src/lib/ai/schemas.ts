import { Type, type Schema } from '@google/genai'
import { createHash } from 'node:crypto'
import { z } from 'zod'
import { vertexSchemaFromZod } from './vertex-schema-adapter'

export const DOCUMENT_TYPES = [
  'DRC-01', 'DRC-01A', 'DRC-01C', 'DRC-03', 'DRC-07', 'SCN', 'OIO', 'OIA',
  'APL-01', 'APL-02', 'APL-05', 'STAY', 'REPLY', 'HC_PETITION', 'HC_ORDER',
  'SC_PETITION', 'SC_ORDER', 'OTHER',
] as const
export const EXTRACTION_SCHEMA_VERSION = 'document-extraction-v3'
export const EXTRACTION_CATALOGUE_VERSION = 'gst-document-and-official-reference-catalogue-v2'
export const EXTRACTION_NORMALIZER_VERSION = 'typed-period-reference-normalizer-v2'
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
const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).superRefine((value, context) => {
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
const nullableGstin = z.string().trim().toUpperCase().regex(/^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/).nullable()
const confidence = z.number().min(0).max(1)

const evidenceSchema = z.object({
  field: z.enum(['document_type', 'gstin', 'client_identifier', 'client_name', 'document_date', 'direction', 'issued_by', 'deadline', 'amount', 'legal_reference']),
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

const legalReferenceSchema = z.object({ act: nullableText,
  provision_type: z.enum(['section', 'rule', 'notification', 'circular', 'instruction', 'other']),
  provision_number: z.string().trim().min(1).max(256), context: nullableText,
  page_number: z.number().int().positive().nullable(), confidence }).strict()
const deadlineSchema = z.object({
  type: z.enum(['appeal_window', 'pre_deposit', 'hearing_date', 'reply_deadline', 'stay_application', 'other']),
  due_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), description: z.string().trim().min(1).max(1024),
  source_page: z.number().int().positive().nullable(), source_quote: nullableText, confidence,
}).strict()

const documentProviderPayloadSchema = z.object({
  doc_type: z.enum(DOCUMENT_TYPES).nullable(), document_title: nullableText,
  document_class: z.enum(['proceeding', 'supporting']),
  document_category: z.enum(['invoice', 'client_document', 'explanation', 'evidence', 'other']).nullable(),
  gstin: nullableGstin, client_identifiers: z.array(z.string().trim().min(1).max(256)).max(50).nullable(),
  client_name: nullableText, doc_date: nullableDate, tax_periods: z.array(taxPeriodSchema).max(30),
  official_references: z.array(officialReferenceSchema).max(100), direction: z.enum(['incoming', 'outgoing']).nullable(),
  issued_by: nullableText, summary: z.string().trim().min(1).max(6000), deadlines: z.array(deadlineSchema).max(50),
  extracted_amounts: z.object({ tax: z.number().finite().nonnegative().nullable(), interest: z.number().finite().nonnegative().nullable(),
    penalty: z.number().finite().nonnegative().nullable(), fee: z.number().finite().nonnegative().nullable(),
    pre_deposit: z.number().finite().nonnegative().nullable(), total_demand: z.number().finite().nonnegative().nullable(),
    amount_in_dispute: z.number().finite().nonnegative().nullable(), amount_relief: z.number().finite().nonnegative().nullable() }).strict(),
  parties_named: z.array(z.string().trim().min(1).max(512)).max(100), legal_references: z.array(legalReferenceSchema).max(100),
  evidence: z.array(evidenceSchema).max(200), confidence,
}).strict()

export const aiDocumentPayloadSchema = documentProviderPayloadSchema.transform((payload) => {
  const selfReference = payload.official_references.find((reference) => reference.role === 'self_identifier' && reference.match_eligible)
  const financialYears = payload.tax_periods.flatMap((period) => period.financial_years).filter((value, index, all) => all.indexOf(value) === index)
  return { ...payload, reference_number: selfReference?.display ?? null, financial_years: financialYears,
    chaining_attributes: { references_documents: payload.official_references.filter((reference) => reference.role === 'outbound_mention' && reference.match_eligible).map((reference) => reference.display),
      gstin: payload.gstin, financial_years: financialYears, matter_ref: null, link_type: null } }
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
