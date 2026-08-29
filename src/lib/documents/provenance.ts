import type { AIDocumentPayload } from '@/lib/ai/schemas'

export type ProvenanceCandidate = {
  semantic_candidate_key: string
  field_path: string
  value_type: 'text' | 'code' | 'date' | 'integer' | 'decimal' | 'boolean'
  normalized_value: string | boolean
  page_number: number
  quotation: string
  evidence_regions: null
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
) {
  if (expectedValue === null || evidence.value !== expectedValue) return
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

  const validation_state = candidateState(evidence.confidence)
  output.push({
    semantic_candidate_key: key,
    field_path: path,
    value_type: valueType,
    normalized_value: expectedValue,
    page_number: pageNumber,
    quotation,
    evidence_regions: null,
    confidence: evidence.confidence,
    validation_state,
    validation_error_codes: candidateErrorCodes(validation_state),
  })
  if (validation_state !== 'eligible') reviewCodes.add(validation_state === 'invalid' ? 'low_confidence' : 'provisional_evidence')
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
    if (evidence) addEvidenceCandidate(candidates, reviewCodes, terminalReviewCodes, evidence, field.value, field.key, field.path, field.type, pageCount)
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
    const validation_state = candidateState(deadline.confidence)
    candidates.push({
      semantic_candidate_key: `deadline:${index}`,
      field_path: 'deadline.due_date',
      value_type: 'date',
      normalized_value: deadline.due_date,
      page_number: deadline.source_page,
      quotation: deadline.source_quote,
      evidence_regions: null,
      confidence: deadline.confidence,
      validation_state,
      validation_error_codes: candidateErrorCodes(validation_state),
    })
    if (validation_state !== 'eligible') reviewCodes.add(validation_state === 'invalid' ? 'low_confidence' : 'provisional_evidence')
  }

  for (const [name, value] of Object.entries(analysis.extracted_amounts)) {
    if (value === null || value === undefined) continue
    const normalized = decimalFromNumber(value)
    const evidence = normalized ? evidenceFor(analysis.evidence, 'amount', normalized) : undefined
    if (!normalized || !evidence) {
      reviewCodes.add('missing_evidence')
      continue
    }
    addEvidenceCandidate(candidates, reviewCodes, terminalReviewCodes, evidence, normalized, `amount:${name}`, `financial.${name}`, 'decimal', pageCount)
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
    )
  }

  return {
    candidates,
    reviewRequired: reviewCodes.size > 0 || terminalReviewCodes.size > 0,
    reviewCodes: [...reviewCodes].sort(),
    terminalReviewRequired: terminalReviewCodes.size > 0,
  }
}
