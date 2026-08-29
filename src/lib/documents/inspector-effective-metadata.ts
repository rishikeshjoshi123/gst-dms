import 'server-only'

import { getCurrentOrgId } from '@/lib/actions/org'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { shapeDocumentInspectorMetadata } from './inspector-metadata-shape'
import type { DocumentInspectorMetadata } from './inspector-metadata-shape'

/**
 * Server-only read boundary for the live inspector. It validates the current
 * caller's membership-visible document set before using the service-only RPC.
 */
export async function getDocumentInspectorMetadata(documentIds: readonly string[]) {
  const uniqueIds = [...new Set(documentIds)]
  if (uniqueIds.length === 0) return {} as Record<string, DocumentInspectorMetadata>

  const requester = await createClient()
  const { data: { user } } = await requester.auth.getUser()
  const orgId = await getCurrentOrgId()
  if (!user || !orgId) return shapeDocumentInspectorMetadata(uniqueIds, [])

  const { data: visibleDocuments } = await requester
    .from('documents')
    .select('id')
    .eq('org_id', orgId)
    .in('id', uniqueIds)
  const visibleIds = (visibleDocuments ?? []).map((document) => document.id)
  if (visibleIds.length === 0) return shapeDocumentInspectorMetadata(uniqueIds, [])

  const { data, error } = await createServiceClient().rpc('read_current_document_inspector_projection', {
    p_org_id: orgId,
    p_document_ids: visibleIds,
  })
  if (error) return shapeDocumentInspectorMetadata(uniqueIds, [])

  return shapeDocumentInspectorMetadata(uniqueIds, data ?? [])
}
