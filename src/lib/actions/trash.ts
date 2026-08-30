'use server'

import { revalidatePath } from 'next/cache'

import { scheduleDocumentOutboxWake } from '@/lib/outbox/wake'
import { createClient } from '@/lib/supabase/server'
import type { TrashResourceType } from '@/lib/trash/workspace-model'

export type RestoreTrashResult = {
  success: boolean
  code: string
  error?: string
  operationId?: string
  blockerCode?: string | null
  blockingOperationId?: string | null
}

function restoreError(code: string) {
  if (code === 'not_allowed') return 'You do not have permission to restore this Trash group.'
  if (code === 'purge_scheduled') return 'Restore is unavailable because permanent deletion has already been scheduled.'
  if (code === 'not_available') return 'This Trash group is no longer available to restore.'
  if (code === 'idempotency_conflict') return 'This Restore request key was already used for another Trash group.'
  if (code === 'invalid_request') return 'This Restore request is invalid. Close the dialog and try again.'
  return 'This Trash group could not be restored. Please try again.'
}

function rootPath(type: TrashResourceType, resourceId: string, matterId: string | null) {
  if (type === 'client') return `/clients/${resourceId}`
  if (type === 'matter') return `/matters/${resourceId}`
  return matterId ? `/matters/${matterId}/documents/${resourceId}` : null
}

export async function restoreTrashOperationAction(
  operationId: string,
  idempotencyKey: string,
): Promise<RestoreTrashResult> {
  const supabase = await createClient()
  const { data: authData } = await supabase.auth.getUser()
  if (!authData.user) return { success: false, code: 'not_allowed', error: 'Not authenticated.' }

  const { data, error } = await supabase.rpc('restore_trash_operation', {
    p_operation_id: operationId,
    p_idempotency_key: idempotencyKey,
  })
  const result = data?.[0]
  if (error || !result) {
    return { success: false, code: 'failed', error: 'This Trash group could not be restored. Please try again.' }
  }

  if (result.code === 'restore_blocked') {
    revalidatePath('/trash')
    return {
      success: false,
      code: result.code,
      operationId: result.operation_id,
      blockerCode: result.blocker_code,
      blockingOperationId: result.blocking_operation_id,
    }
  }
  if (result.code !== 'restored') {
    return { success: false, code: result.code, error: restoreError(result.code) }
  }

  revalidatePath('/trash')
  revalidatePath('/dashboard')
  revalidatePath('/clients')
  revalidatePath('/matters')
  revalidatePath('/documents')
  revalidatePath('/search')
  const canonicalPath = rootPath(result.root_resource_type, result.root_resource_id, result.root_matter_id)
  if (canonicalPath) revalidatePath(canonicalPath)
  if (result.root_client_id) revalidatePath(`/clients/${result.root_client_id}`)
  if (result.root_matter_id) revalidatePath(`/matters/${result.root_matter_id}`)
  // The transaction already owns the durable Restore intents. This is only a
  // best-effort immediate wake; scheduled recovery remains authoritative.
  scheduleDocumentOutboxWake()

  return { success: true, code: result.code, operationId: result.operation_id }
}
