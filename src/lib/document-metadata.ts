import type { AIDocumentResult } from '@/lib/ai/vertex'

/**
 * Converts a completed AI analysis into the canonical document columns used by
 * the timeline, detail panel, search, and assignment rules. Keep this mapping
 * shared so an inbox handoff cannot leave data stranded in raw_metadata.
 */
export function documentColumnsFromAnalysis(
  analysis: AIDocumentResult,
  financialYear: string | null,
) {
  return {
    doc_type: analysis.doc_type || 'OTHER',
    reference_number: analysis.reference_number || null,
    doc_date: analysis.doc_date || null,
    direction: analysis.direction || 'incoming',
    issued_by: analysis.issued_by || null,
    document_class: analysis.document_class || 'proceeding',
    document_category: analysis.document_category || null,
    financial_year: financialYear,
    summary: analysis.summary || null,
    raw_metadata: analysis,
  }
}
