import type { AIDocumentPayload } from '@/lib/ai/schemas'
import { verifyCanonicalSource, type CanonicalPage } from './source-verifier'

export type ProvenanceCandidate = {
  semantic_candidate_key: string
  field_path: string
  value_type: 'text' | 'code' | 'date' | 'integer' | 'decimal' | 'boolean'
  normalized_value: string | boolean
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

  const scalarFields: Array<{
    evidenceField: EvidenceField
    value: string | null
    key: string
    path: string
    type: ProvenanceCandidate['value_type']
  }> = [
    { evidenceField: 'document_type', value: analysis.doc_type, key: 'document.type', path: 'document.type', type: 'code' },
    { evidenceField: 'reference_number', value: analysis.reference_number, key: 'document.reference_number', path: 'document.reference_number', type: 'text' },
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

  for (const [index, financialYear] of analysis.financial_years.entries()) {
    const evidence = evidenceFor(analysis.evidence, 'financial_year', financialYear)
    if (!evidence) {
      reviewCodes.add('missing_evidence')
      continue
    }
    addEvidenceCandidate(
      candidates,
      reviewCodes,
      terminalReviewCodes,
      evidence,
      financialYear,
      `financial_year:${index}`,
      'document.financial_year',
      'code',
      pageCount,
      pages,
    )
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

  for (const reference of analysis.chaining_attributes.references_documents) {
    const evidence = evidenceFor(analysis.evidence, 'document_link', reference)
    if (!evidence) {
      reviewCodes.add('missing_evidence')
      continue
    }
    addEvidenceCandidate(
      candidates,
      reviewCodes,
      terminalReviewCodes,
      evidence,
      reference,
      `referenced_document:${reference}`,
      'document.referenced_document_number',
      'text',
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
