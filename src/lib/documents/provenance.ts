import { createHash } from 'node:crypto'
import {
  actorSemanticKey,
  clientIdentifierSemanticKey,
  legalDateSemanticKey,
  legalProvisionSemanticKey,
  moneyObservationSemanticKey,
  officialReferenceSemanticKey,
  partySemanticKey,
  type AIDocumentPayload,
} from '@/lib/ai/schemas'
import type { Json } from '@/lib/supabase/database.types'
import { verifyCanonicalSource, type CanonicalPage } from './source-verifier'

export type ProvenanceCandidate = {
  semantic_candidate_key: string
  field_path: string
  value_type: 'text' | 'code' | 'date' | 'integer' | 'decimal' | 'boolean' | 'structured'
  normalized_value: Json
  page_number: number
  quotation: string
  verified_source_anchor: {
    char_start: number
    char_end: number
    token_start: number | null
    token_end: number | null
    table_cell: { table_index: number; row_index: number; column_index: number } | null
  } | null
  evidence_regions: Array<{ x: number; y: number; width: number; height: number }> | null
  confidence: number
  validation_state: 'eligible' | 'provisional' | 'conflicting' | 'invalid'
  validation_error_codes: string[] | null
}

export type ProvenanceMaterialization = {
  candidates: ProvenanceCandidate[]
  reviewRequired: boolean
  reviewCodes: string[]
  terminalReviewRequired: boolean
}

type EvidenceField = AIDocumentPayload['evidence'][number]['field']

const ELIGIBLE_CONFIDENCE = 0.85
const PROVISIONAL_CONFIDENCE = 0.6

function candidateState(confidence: number): ProvenanceCandidate['validation_state'] {
  if (confidence >= ELIGIBLE_CONFIDENCE) return 'eligible'
  if (confidence >= PROVISIONAL_CONFIDENCE) return 'provisional'
  return 'invalid'
}

function candidateErrorCodes(state: ProvenanceCandidate['validation_state']) {
  return state === 'invalid' ? ['low_confidence'] : null
}

function addEvidenceCandidate(
  output: ProvenanceCandidate[],
  reviewCodes: Set<string>,
  terminalReviewCodes: Set<string>,
  evidence: AIDocumentPayload['evidence'][number],
  expectedValue: string | null,
  key: string,
  path: string,
  valueType: ProvenanceCandidate['value_type'],
  pageCount: number,
  pages: CanonicalPage[] | undefined,
) {
  if (expectedValue === null) return
  const pageNumber = evidence.page_number
  const quotation = evidence.quote
  if (pageNumber === null || quotation === null) {
    reviewCodes.add('missing_evidence')
    return
  }
  if (pageNumber > pageCount || quotation.length > 1000 || /[\u0000-\u001F\u007F]/.test(quotation)) {
    terminalReviewCodes.add('candidate_evidence_unsafe')
    return
  }
  if ((valueType === 'text' && (expectedValue.length > 1024 || /[\u0000-\u001F\u007F]/.test(expectedValue)))
    || (valueType === 'code' && !/^[A-Za-z0-9][A-Za-z0-9 .,/()&+#:_-]{0,255}$/.test(expectedValue))) {
    terminalReviewCodes.add('candidate_value_unsafe')
    return
  }

  const critical = valueType === 'date' || valueType === 'decimal' || key.includes('gstin') || key.includes('identifier') || key.includes('reference') || key.includes('deadline') || key.includes('matter') || key.includes('client')
  // `client_identifier` deliberately holds heterogeneous identifiers (PAN,
  // TAN, CIN, registrations, and client-specific references). Only the
  // explicit GSTIN field receives GSTIN syntax/checksum verification; generic
  // identifiers remain source-bound without being misclassified as tax IDs.
  const identifier = key === 'document.gstin' ? 'gstin' : undefined
  // Critical candidates must always resolve against a canonical page. An
  // unavailable acquisition is the same fail-closed field exception as a
  // missing page, never an eligible candidate that would abort SQL completion.
  const verification = critical
    ? verifyCanonicalSource(pages?.find((page) => page.page_number === pageNumber), quotation, expectedValue, valueType === 'code' ? 'code' : valueType === 'date' ? 'date' : valueType === 'decimal' ? 'decimal' : 'text', identifier)
    : null
  const validation_state = verification && !verification.ok ? 'invalid' : candidateState(evidence.confidence)
  const validation_error_codes = verification && !verification.ok
    ? [verification.code]
    : candidateErrorCodes(validation_state)
  output.push({
    semantic_candidate_key: key,
    field_path: path,
    value_type: valueType,
    normalized_value: expectedValue,
    page_number: pageNumber,
    quotation,
    verified_source_anchor: verification?.ok ? {
      char_start: verification.evidence.char_start,
      char_end: verification.evidence.char_end,
      token_start: verification.evidence.token_start,
      token_end: verification.evidence.token_end,
      table_cell: verification.evidence.table_cell,
    } : null,
    evidence_regions: verification?.ok && verification.evidence.regions.length ? verification.evidence.regions : null,
    confidence: evidence.confidence,
    validation_state,
    validation_error_codes,
  })
  if (validation_state !== 'eligible') reviewCodes.add(validation_state === 'invalid' ? (verification && !verification.ok ? verification.code : 'low_confidence') : 'provisional_evidence')
}

function evidenceFor(
  evidence: AIDocumentPayload['evidence'],
  field: EvidenceField,
  value: string,
) {
  return evidence.find((item) => item.field === field && item.value === value)
}

type StructuredObservation = {
  raw: string
  source_page: number
  source_quote: string
  confidence: number
  normalization_state?: 'valid' | 'provisional' | 'invalid'
  validation_error?: string | null
}

function addStructuredCandidate(
  output: ProvenanceCandidate[],
  reviewCodes: Set<string>,
  terminalReviewCodes: Set<string>,
  observation: StructuredObservation,
  semanticKey: string,
  fieldPath: string,
  pageCount: number,
  pages: CanonicalPage[] | undefined,
  sourceValue = observation.raw,
  sourceType: 'text' | 'code' | 'date' | 'decimal' = 'text',
  identifier?: 'gstin',
  alwaysProvisional = false,
  domainError?: string,
  sourceGroundingError?: string,
) {
  if (observation.source_page > pageCount || /[\u0000-\u001F\u007F]/.test(observation.source_quote)) {
    terminalReviewCodes.add('candidate_evidence_unsafe')
    return
  }
  const verification = verifyCanonicalSource(
    pages?.find((page) => page.page_number === observation.source_page),
    observation.source_quote,
    sourceValue,
    sourceType,
    identifier,
  )
  const { source_page, source_quote, confidence, ...normalized } = observation
  const sourceVerified = verification.ok && sourceGroundingError === undefined
  const validation_state: ProvenanceCandidate['validation_state'] = !sourceVerified || domainError ? 'invalid'
    : observation.normalization_state === 'invalid' ? 'invalid'
    : alwaysProvisional || observation.normalization_state === 'provisional' ? 'provisional'
    : candidateState(confidence)
  const validation_error_codes = validation_state === 'invalid'
    ? [!verification.ok ? verification.code : sourceGroundingError ?? domainError ?? observation.validation_error ?? 'domain_invalid']
    : null
  output.push({
    semantic_candidate_key: semanticKey,
    field_path: fieldPath,
    value_type: 'structured',
    normalized_value: normalized as Json,
    page_number: source_page,
    quotation: source_quote,
    verified_source_anchor: verification.ok && sourceGroundingError === undefined ? {
      char_start: verification.evidence.char_start,
      char_end: verification.evidence.char_end,
      token_start: verification.evidence.token_start,
      token_end: verification.evidence.token_end,
      table_cell: verification.evidence.table_cell,
    } : null,
    evidence_regions: verification.ok && sourceGroundingError === undefined && verification.evidence.regions.length ? verification.evidence.regions : null,
    confidence,
    validation_state,
    validation_error_codes,
  })
  if (validation_state !== 'eligible') {
    reviewCodes.add(validation_state === 'invalid' ? validation_error_codes![0] : 'provisional_evidence')
  }
}

const LEGAL_ACT_SOURCE_ALIASES: Partial<Record<AIDocumentPayload['legal_provisions'][number]['act_kind'], string[]>> = {
  cgst_act: ['CGST ACT', 'CENTRAL GOODS AND SERVICES TAX ACT'],
  igst_act: ['IGST ACT', 'INTEGRATED GOODS AND SERVICES TAX ACT'],
  gst_rules: ['GST RULES', 'CGST RULES', 'CENTRAL GOODS AND SERVICES TAX RULES'],
  constitution: ['CONSTITUTION', 'CONSTITUTION OF INDIA'],
}

function canonicalSourceLabel(value: string) {
  return value.normalize('NFKC').replace(/\uFEFF/gu, ' ').toUpperCase().replace(/\s+/gu, ' ').trim()
}

function legalProvisionSourceGroundingError(provision: AIDocumentPayload['legal_provisions'][number]) {
  if (provision.normalization_state === 'invalid') return undefined
  const quote = canonicalSourceLabel(provision.source_quote)
  if (provision.act && !quote.includes(canonicalSourceLabel(provision.act))) return 'act_not_in_quote'
  const aliases = LEGAL_ACT_SOURCE_ALIASES[provision.act_kind]
  if (aliases && !aliases.some((alias) => quote.includes(alias))) return 'act_kind_not_in_quote'
  if (provision.act_kind === 'other_catalogued' && provision.act === null) return 'act_not_in_quote'
  return undefined
}

/**
 * Turns a structurally valid model payload into the bounded scalar contract
 * accepted by the source-candidate authority. Every automatic candidate has
 * a source page and a short quotation; unsupported or uncertain facts become
 * a safe Review exception instead of an unverifiable projection.
 */
export function provenanceMaterializationFromAnalysis(
  analysis: AIDocumentPayload,
  pageCount: number,
  pages?: CanonicalPage[],
): ProvenanceMaterialization {
  const candidates: ProvenanceCandidate[] = []
  const reviewCodes = new Set<string>()
  const terminalReviewCodes = new Set<string>()

  for (const period of analysis.tax_periods) {
    if (period.source_page > pageCount || /[\u0000-\u001F\u007F]/.test(period.source_quote)) {
      terminalReviewCodes.add('candidate_evidence_unsafe')
      continue
    }
    const verification = verifyCanonicalSource(
      pages?.find((page) => page.page_number === period.source_page),
      period.source_quote, period.raw, 'text',
    )
    const { source_page, source_quote, confidence, ...normalized } = period
    const digest = createHash('sha256').update(JSON.stringify([
      normalized.kind, normalized.segments, normalized.printed_financial_years,
    ])).digest('hex').slice(0, 32)
    const validation_state: ProvenanceCandidate['validation_state'] = !verification.ok ? 'invalid'
      : period.conflict ? 'conflicting'
      : period.kind === 'unclear' ? 'provisional'
      : candidateState(confidence)
    const validation_error_codes = validation_state === 'invalid'
      ? [verification.ok ? 'low_confidence' : verification.code] : null
    candidates.push({ semantic_candidate_key: `tax_period:${digest}`, field_path: 'document.tax_period',
      value_type: 'structured', normalized_value: normalized, page_number: source_page, quotation: source_quote,
      verified_source_anchor: verification.ok ? { char_start: verification.evidence.char_start, char_end: verification.evidence.char_end,
        token_start: verification.evidence.token_start, token_end: verification.evidence.token_end, table_cell: verification.evidence.table_cell } : null,
      evidence_regions: verification.ok && verification.evidence.regions.length ? verification.evidence.regions : null,
      confidence, validation_state, validation_error_codes })
    if (!verification.ok) reviewCodes.add(verification.code)
    else if (period.conflict) reviewCodes.add('printed_derived_financial_year_conflict')
    else if (validation_state !== 'eligible') reviewCodes.add(validation_state === 'invalid' ? 'low_confidence' : 'provisional_evidence')
  }

  for (const reference of analysis.official_references) {
    if (reference.source_page > pageCount || /[\u0000-\u001F\u007F]/.test(reference.source_quote)) {
      terminalReviewCodes.add('candidate_evidence_unsafe')
      continue
    }
    const verification = verifyCanonicalSource(
      pages?.find((page) => page.page_number === reference.source_page),
      reference.source_quote, reference.normalized_value ?? reference.raw, 'code',
    )
    const { source_page, source_quote, confidence, ...normalized } = reference
    // Source validation is not human verification. Official references remain
    // provisional and cannot feed identifier authority or relationship effects.
    const validation_state: ProvenanceCandidate['validation_state'] = verification.ok ? 'provisional' : 'invalid'
    candidates.push({ semantic_candidate_key: officialReferenceSemanticKey(reference),
      field_path: `document.official_reference.${reference.role}`, value_type: 'structured',
      normalized_value: normalized, page_number: source_page, quotation: source_quote,
      verified_source_anchor: verification.ok ? { char_start: verification.evidence.char_start, char_end: verification.evidence.char_end,
        token_start: verification.evidence.token_start, token_end: verification.evidence.token_end, table_cell: verification.evidence.table_cell } : null,
      evidence_regions: verification.ok && verification.evidence.regions.length ? verification.evidence.regions : null,
      confidence, validation_state, validation_error_codes: verification.ok ? null : [verification.code] })
    reviewCodes.add(verification.ok ? 'unverified_official_reference' : verification.code)
  }

  const scalarFields: Array<{
    evidenceField: EvidenceField
    value: string | null
    key: string
    path: string
    type: ProvenanceCandidate['value_type']
  }> = [
    { evidenceField: 'document_type', value: analysis.doc_type, key: 'document.type', path: 'document.type', type: 'code' },
    { evidenceField: 'client_name', value: analysis.client_name, key: 'document.client_name', path: 'document.client_name', type: 'text' },
  ]

  for (const field of scalarFields) {
    const evidence = field.value === null ? undefined : evidenceFor(analysis.evidence, field.evidenceField, field.value)
    if (field.value !== null && !evidence) reviewCodes.add('missing_evidence')
    if (evidence) addEvidenceCandidate(candidates, reviewCodes, terminalReviewCodes, evidence, field.value, field.key, field.path, field.type, pageCount, pages)
  }

  for (const identifier of analysis.client_identifiers_observed) {
    addStructuredCandidate(candidates, reviewCodes, terminalReviewCodes, identifier,
      clientIdentifierSemanticKey(identifier), `document.client_identifier.${identifier.kind}`, pageCount, pages,
      identifier.normalized_value ?? identifier.raw, 'code', identifier.kind === 'gstin' && identifier.normalized_value ? 'gstin' : undefined, true)
  }

  for (const date of analysis.legal_dates) {
    addStructuredCandidate(candidates, reviewCodes, terminalReviewCodes, date,
      legalDateSemanticKey(date), `document.legal_date.${date.meaning}`, pageCount, pages,
      date.normalized_date ?? date.raw, date.normalized_date ? 'date' : 'text', undefined, true)
  }

  for (const actor of analysis.actors) {
    const supported = [actor.authority, actor.office, actor.jurisdiction].filter((value): value is string => value !== null)
      .every((value) => actor.source_quote.normalize('NFKC').toUpperCase().includes(value.normalize('NFKC').toUpperCase()))
    addStructuredCandidate(candidates, reviewCodes, terminalReviewCodes, actor,
      actorSemanticKey(actor), `document.actor.${actor.actor_kind}`, pageCount, pages, actor.raw, 'text', undefined, true,
      supported ? undefined : 'unsupported_actor_normalization')
  }

  for (const party of analysis.parties) {
    addStructuredCandidate(candidates, reviewCodes, terminalReviewCodes, party,
      partySemanticKey(party), `document.party.${party.procedural_role}`, pageCount, pages,
      party.raw, 'text', undefined, true)
  }

  for (const money of analysis.money_observations) {
    addStructuredCandidate(candidates, reviewCodes, terminalReviewCodes, money,
      moneyObservationSemanticKey(money), `document.money.${money.component}`, pageCount, pages,
      money.amount, 'decimal', undefined, true)
  }

  for (const provision of analysis.legal_provisions) {
    addStructuredCandidate(candidates, reviewCodes, terminalReviewCodes, provision,
      legalProvisionSemanticKey(provision), `document.legal_provision.${provision.provision_kind}`, pageCount, pages,
      provision.normalized?.value ?? provision.raw, provision.normalized ? 'code' : 'text', undefined, true, undefined,
      legalProvisionSourceGroundingError(provision))
  }

  return {
    candidates,
    reviewRequired: reviewCodes.size > 0 || terminalReviewCodes.size > 0,
    reviewCodes: [...reviewCodes].sort(),
    terminalReviewRequired: terminalReviewCodes.size > 0,
  }
}
