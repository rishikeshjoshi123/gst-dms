import 'server-only'

import { getCurrentOrgId } from '@/lib/actions/org'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { shapeMatterRelationshipMetadata, type EffectiveMatterRelationshipDocument, type RelationshipProjectionRow } from './matter-relationship-metadata-shape'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/lib/supabase/database.types'

export type { EffectiveMatterRelationshipDocument } from './matter-relationship-metadata-shape'

/**
 * Authorises the browser caller for this exact active matter before a
 * service-only relationship projection is read. No browser caller receives
 * raw metadata or direct projection-table access.
 */
export async function getCurrentMatterRelationshipMetadata(matterId: string) {
  const requester = await createClient()
  const { data: { user } } = await requester.auth.getUser()
  const orgId = await getCurrentOrgId()
  if (!user || !orgId) return { orgId: null, documents: [] as EffectiveMatterRelationshipDocument[] }

  const { data: matter } = await requester
    .from('matters')
    .select('id')
    .eq('id', matterId)
    .eq('org_id', orgId)
    .is('deleted_at', null)
    .maybeSingle()
  if (!matter) return { orgId: null, documents: [] as EffectiveMatterRelationshipDocument[] }

  const { data, error } = await createServiceClient().rpc('read_current_matter_relationship_projection', {
    p_org_id: orgId,
    p_matter_id: matter.id,
  })
  if (error) return { orgId: null, documents: [] as EffectiveMatterRelationshipDocument[] }
  return { orgId, documents: shapeMatterRelationshipMetadata((data ?? []) as RelationshipProjectionRow[]) }
}

export async function fuzzyCurrentMatterRelationshipReference(orgId: string, matterId: string, referenceNumber: string) {
  const { data, error } = await createServiceClient().rpc('fuzzy_match_current_matter_relationship_reference', {
    p_org_id: orgId,
    p_matter_id: matterId,
    p_reference_number: referenceNumber,
  })
  if (error || !data?.[0]) return null
  return data[0]
}

export async function currentRelationshipReferenceExistsInOtherMatter(orgId: string, matterId: string, referenceNumber: string) {
  const { data, error } = await createServiceClient().rpc('current_relationship_reference_exists_in_other_matter', {
    p_org_id: orgId,
    p_matter_id: matterId,
    p_reference_number: referenceNumber,
  })
  return !error && data === true
}

export type ProcessingRelationshipPlacementArgs = Database['public']['Functions']['place_document_processing_relationships']['Args']
export type ProcessingRelationshipPlacementResult = Database['public']['Functions']['place_document_processing_relationships']['Returns'][number]

/**
 * The Trigger worker's only relationship-placement boundary. The database
 * command re-reads current valid effective values and applies all mutations
 * atomically, so this helper never accepts an AI payload or raw metadata.
 */
export async function placeProcessingDocumentRelationships(
  supabase: SupabaseClient<Database>,
  args: ProcessingRelationshipPlacementArgs,
): Promise<ProcessingRelationshipPlacementResult | null> {
  const { data, error } = await supabase.rpc('place_document_processing_relationships', args)
  if (error) throw new Error('Document relationship placement RPC unavailable')
  return data?.[0] ?? null
}
