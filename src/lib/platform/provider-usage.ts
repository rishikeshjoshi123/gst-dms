import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/lib/supabase/database.types'

export type DocumentExtractionUsageWriteCode =
  | 'recorded_priced'
  | 'recorded_unpriced'
  | 'replayed'
  | 'configuration_unavailable'
  | 'usage_not_reported'
  | 'invalid_subject'
  | 'invalid_request'
  | 'writer_unavailable'
  | 'writer_response_invalid'

const documentExtractionUsageWriteCodes = new Set<DocumentExtractionUsageWriteCode>([
  'recorded_priced',
  'recorded_unpriced',
  'replayed',
  'configuration_unavailable',
  'usage_not_reported',
  'invalid_subject',
  'invalid_request',
])

/**
 * Appends usage only from the completed, server-owned provenance run. The SQL
 * writer derives organisation, provider/model, exact token counts, and opaque
 * idempotency itself; this adapter deliberately has no content-bearing input.
 */
export async function recordCompletedDocumentExtractionProviderUsage(
  supabase: SupabaseClient<Database>,
  sourceAnalysisRunId: string,
): Promise<DocumentExtractionUsageWriteCode> {
  const { data, error } = await supabase.rpc(
    'record_completed_document_extraction_provider_usage',
    { p_source_analysis_run_id: sourceAnalysisRunId },
  )
  if (error) return 'writer_unavailable'

  const code = Array.isArray(data) ? data[0]?.code : undefined
  return typeof code === 'string' && documentExtractionUsageWriteCodes.has(code as DocumentExtractionUsageWriteCode)
    ? code as DocumentExtractionUsageWriteCode
    : 'writer_response_invalid'
}

/** Fixed, content-free observability for a non-authoritative accounting failure. */
export function logDocumentExtractionUsageWriteOutcome(code: DocumentExtractionUsageWriteCode) {
  if (code === 'recorded_priced' || code === 'recorded_unpriced' || code === 'replayed') return
  console.warn(`[Provider usage] document_extraction_${code}`)
}
