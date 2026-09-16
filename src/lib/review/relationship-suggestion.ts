import type { ReviewDetail } from './model'

export type RelationshipSuggestionEvidence = {
  source_document_id: string
  source_document_version_id: string
  source_document_title: string
  target_document_id: string
  target_document_version_id: string
  target_document_title: string
  identifier_kind: string
  namespace: string
  normalized_value: string
}

export type TimelineRelationshipReviewCandidate = {
  sourceDocumentId: string
  targetDocumentId: string
}

export function relationshipSuggestionEvidence(item: ReviewDetail): RelationshipSuggestionEvidence | null {
  const value = item.evidence[0]?.value
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const row = value as Partial<RelationshipSuggestionEvidence>
  return typeof row.source_document_id === 'string'
    && typeof row.source_document_version_id === 'string'
    && typeof row.source_document_title === 'string'
    && typeof row.target_document_id === 'string'
    && typeof row.target_document_version_id === 'string'
    && typeof row.target_document_title === 'string'
    ? row as RelationshipSuggestionEvidence
    : null
}

export function timelineRelationshipReviewCandidate(item: ReviewDetail | null): TimelineRelationshipReviewCandidate | null {
  if (item?.type !== 'relationship_suggestion') return null
  const evidence = relationshipSuggestionEvidence(item)
  return evidence ? { sourceDocumentId: evidence.source_document_id, targetDocumentId: evidence.target_document_id } : null
}
