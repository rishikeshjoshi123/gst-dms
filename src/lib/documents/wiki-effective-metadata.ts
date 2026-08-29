import 'server-only'

import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/lib/supabase/database.types'

/** Service-only bounded reader for the current effective Wiki metadata. */
export async function readCurrentDocumentWikiMetadata(
  supabase: SupabaseClient<Database>,
  orgId: string,
  documentIds: readonly string[],
) {
  if (documentIds.length === 0) return []
  const { data, error } = await supabase.rpc('read_current_document_effective_metadata', {
    p_org_id: orgId,
    p_document_ids: [...new Set(documentIds)],
  })
  if (error) throw new Error('Current effective document metadata reader unavailable')
  return data ?? []
}
