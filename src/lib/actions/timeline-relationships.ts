'use server'

import { refresh, revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { activateRelationshipSchema, archiveRelationshipSchema, relationshipCommandResult, type ActivateRelationshipInput, type ArchiveRelationshipInput } from '@/lib/matters/relationship-authoring'

export async function activateTimelineRelationship(input: ActivateRelationshipInput) {
  const parsed = activateRelationshipSchema.safeParse(input)
  if (!parsed.success) return relationshipCommandResult('invalid_request')
  const value = parsed.data
  const client = await createClient()
  const { data: auth, error: authError } = await client.auth.getUser()
  if (authError || !auth.user) return relationshipCommandResult('not_allowed')
  // The authenticated command derives membership, capability and lifecycle authority.
  const { data, error } = await client.rpc('activate_matter_timeline_relationship', {
    p_matter_id: value.matterId, p_source_document_id: value.sourceId,
    p_target_document_id: value.targetId, p_relationship_type: value.relationshipType,
    p_expected_source_revision: value.sourceRevision, p_expected_target_revision: value.targetRevision,
    p_expected_catalogue_version: value.catalogueVersion,
    p_reason: value.reason, p_idempotency_key: value.idempotencyKey,
  })
  const result = relationshipCommandResult(error ? 'unknown' : data?.[0]?.code ?? 'unknown', data?.[0]?.replayed)
  if (result.refresh) { revalidatePath(`/matters/${value.matterId}`); refresh() }
  return result
}

export async function archiveTimelineRelationship(input: ArchiveRelationshipInput) {
  const parsed = archiveRelationshipSchema.safeParse(input)
  if (!parsed.success) return relationshipCommandResult('invalid_request')
  const value = parsed.data
  const client = await createClient()
  const { data: auth, error: authError } = await client.auth.getUser()
  if (authError || !auth.user) return relationshipCommandResult('not_allowed')
  const { data, error } = await client.rpc('archive_matter_timeline_relationship', {
    p_matter_id: value.matterId,
    p_relationship_id: value.relationshipId, p_expected_revision: value.revision,
    p_reason: value.reason, p_idempotency_key: value.idempotencyKey,
  })
  const result = relationshipCommandResult(error ? 'unknown' : data?.[0]?.code ?? 'unknown', data?.[0]?.replayed)
  if (result.refresh) { revalidatePath(`/matters/${value.matterId}`); refresh() }
  return result
}
