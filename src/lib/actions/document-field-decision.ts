'use server'

import { revalidatePath } from 'next/cache'
import { getCurrentOrgId } from '@/lib/actions/org'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { replacementValue, type EditableFieldPath } from '@/lib/documents/inspector-field-correction'
export type { EditableFieldPath } from '@/lib/documents/inspector-field-correction'

export type InspectorFieldCorrection = {
  documentId: string
  documentVersionId: string
  candidateId: string
  fieldPath: EditableFieldPath
  value: string
  idempotencyKey: string
}

/** Server-only command that appends a correction for the exact current candidate. */
export async function correctInspectorField(input: InspectorFieldCorrection) {
  const replacement = replacementValue(input.fieldPath, input.value)
  if (!replacement || !/^inspector:[a-z0-9-]{36}$/.test(input.idempotencyKey)) {
    return { error: 'Enter a valid value and try again.' }
  }

  const requester = await createClient()
  const { data: { user } } = await requester.auth.getUser()
  const orgId = await getCurrentOrgId()
  if (!user || !orgId) return { error: 'You are not authorised to correct this field.' }

  const { data: visibleDocument } = await requester
    .from('documents')
    .select('id, matter_id, current_version_id')
    .eq('id', input.documentId)
    .eq('org_id', orgId)
    .is('deleted_at', null)
    .maybeSingle()
  if (!visibleDocument || visibleDocument.current_version_id !== input.documentVersionId) {
    return { error: 'This document version is no longer available. Refresh and try again.' }
  }

  const { error } = await createServiceClient().rpc('record_current_document_inspector_correction', {
    p_org_id: orgId,
    p_document_id: visibleDocument.id,
    p_document_version_id: input.documentVersionId,
    p_document_field_candidate_id: input.candidateId,
    p_field_path: input.fieldPath,
    p_replacement_value: replacement,
    p_actor_user_id: user.id,
    p_idempotency_key: input.idempotencyKey,
  })
  if (error) return { error: 'Unable to record this correction. Please try again.' }

  revalidatePath(`/matters/${visibleDocument.matter_id}`)
  revalidatePath(`/matters/${visibleDocument.matter_id}/documents/${visibleDocument.id}`)
  return { success: true }
}
