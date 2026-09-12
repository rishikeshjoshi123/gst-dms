import { createHash } from 'node:crypto'
import { officialReferenceSemanticKey, type AIDocumentPayload } from '@/lib/ai/schemas'
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

function decimalFromNumber(value: number) {
  const normalized = String(value)
  return /^-?(0|[1-9][0-9]{0,17})(\.[0-9]{1,6})?$/.test(normalized) ? normalized : null
}

function evidenceFor(
  evidence: AIDocumentPayload['evidence'],
  field: EvidenceField,
  value: string,
) {
  return evidence.find((item) => item.field === field && item.value === value)
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
    { evidenceField: 'gstin', value: analysis.gstin, key: 'document.gstin', path: 'document.gstin', type: 'code' },
    { evidenceField: 'client_name', value: analysis.client_name, key: 'document.client_name', path: 'document.client_name', type: 'text' },
    { evidenceField: 'document_date', value: analysis.doc_date, key: 'document.date', path: 'document.date', type: 'date' },
    { evidenceField: 'direction', value: analysis.direction, key: 'document.direction', path: 'document.direction', type: 'code' },
    { evidenceField: 'issued_by', value: analysis.issued_by, key: 'document.issued_by', path: 'document.issued_by', type: 'text' },
  ]

  for (const field of scalarFields) {
    const evidence = field.value === null ? undefined : evidenceFor(analysis.evidence, field.evidenceField, field.value)
    if (field.value !== null && !evidence) reviewCodes.add('missing_evidence')
    if (evidence) addEvidenceCandidate(candidates, reviewCodes, terminalReviewCodes, evidence, field.value, field.key, field.path, field.type, pageCount, pages)
  }

  for (const identifier of analysis.client_identifiers ?? []) {
    const evidence = evidenceFor(analysis.evidence, 'client_identifier', identifier)
    if (!evidence) {
      reviewCodes.add('missing_evidence')
      continue
    }
    addEvidenceCandidate(
      candidates,
      reviewCodes,
      terminalReviewCodes,
      evidence,
      identifier,
      `client_identifier:${identifier}`,
      'document.client_identifier',
      'code',
      pageCount,
      pages,
    )
  }

  for (const [index, deadline] of analysis.deadlines.entries()) {
    if (deadline.source_page === null || deadline.source_quote === null) {
      reviewCodes.add('missing_evidence')
      continue
    }
    if (deadline.source_page > pageCount || deadline.source_quote.length > 1000 || /[\u0000-\u001F\u007F]/.test(deadline.source_quote)) {
      terminalReviewCodes.add('candidate_evidence_unsafe')
      continue
    }
    addEvidenceCandidate(candidates, reviewCodes, terminalReviewCodes, {
      field: 'deadline', value: deadline.due_date, page_number: deadline.source_page,
      quote: deadline.source_quote, confidence: deadline.confidence,
    }, deadline.due_date, `deadline:${index}`, 'deadline.due_date', 'date', pageCount, pages)
  }

  for (const [name, value] of Object.entries(analysis.extracted_amounts)) {
    if (value === null || value === undefined) continue
    const normalized = decimalFromNumber(value)
    const evidence = normalized ? evidenceFor(analysis.evidence, 'amount', normalized) : undefined
    if (!normalized || !evidence) {
      reviewCodes.add('missing_evidence')
      continue
    }
    addEvidenceCandidate(candidates, reviewCodes, terminalReviewCodes, evidence, normalized, `amount:${name}`, `financial.${name}`, 'decimal', pageCount, pages)
  }

  for (const [index, reference] of analysis.legal_references.entries()) {
    const evidence = evidenceFor(analysis.evidence, 'legal_reference', reference.provision_number)
    if (!evidence) {
      reviewCodes.add('missing_evidence')
      continue
    }
    addEvidenceCandidate(
      candidates,
      reviewCodes,
      terminalReviewCodes,
      evidence,
      reference.provision_number,
      `legal_reference:${index}`,
      'legal_reference.provision_number',
      'code',
      pageCount,
      pages,
    )
  }

  return {
    candidates,
    reviewRequired: reviewCodes.size > 0 || terminalReviewCodes.size > 0,
    reviewCodes: [...reviewCodes].sort(),
    terminalReviewRequired: terminalReviewCodes.size > 0,
  }
}
