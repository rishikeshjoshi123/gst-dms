'use server'

import { createClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'
import { scheduleDocumentOutboxWake } from '@/lib/outbox/wake'
import { randomUUID } from 'node:crypto'
import { isOpenMatter, normalizeMatterState } from '@/lib/matters/matter-state'

// ── Read Clients ──────────────────────────────────────────────────

export async function getClients() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data } = await supabase
    .from('clients')
    .select('*, matters(id, status, work_state, current_forum)')
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .eq('matters.record_state', 'active')
    .is('matters.deleted_at', null)
    .order('name')

  if (!data) return []

  return data.map((client) => {
    const activeMatters = (client.matters || []).map(normalizeMatterState)
    return {
      ...client,
      totalMatters: activeMatters.length,
      openMatters: activeMatters.filter(isOpenMatter).length
    }
  })
}

export async function getClientById(id: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return null

  const { data } = await supabase
    .from('clients')
    .select('*')
    .eq('id', id)
    .eq('org_id', orgId)
    .is('deleted_at', null)
    .single()

  return data
}

// ── Create Client ─────────────────────────────────────────────────

export async function createClientAction(formData: FormData) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  
  if (!orgId) return { error: 'No active organisation.' }

  const name = (formData.get('name') as string)?.trim()
  const gstin = (formData.get('gstin') as string)?.trim() || null
  const pan = (formData.get('pan') as string)?.trim() || null
  const idempotencyKey = (formData.get('idempotencyKey') as string)?.trim() || randomUUID()

  if (!name || name.length < 2) {
    return { error: 'Client name must be at least 2 characters.' }
  }

  const { data: command, error: commandError } = await supabase.rpc('create_client_command', {
    p_name: name,
    p_gstin: gstin ?? '',
    p_pan: pan ?? '',
    p_idempotency_key: idempotencyKey,
  })
  const result = command?.[0]
  if (commandError || !result || result.code !== 'ok' || !result.client_id) {
    console.error('Create client command error:', commandError ?? result?.code)
    const messages: Record<string, string> = {
      invalid_request: 'Check the client name, GSTIN, and PAN.',
      not_allowed: 'You do not have permission to create clients.',
      identifier_conflict: 'An active client already uses this GSTIN or PAN.',
      idempotency_conflict: 'This submission key was already used for another request.',
      context_unavailable: 'The created client is no longer active.',
    }
    return { error: messages[result?.code ?? ''] ?? 'Failed to create client.' }
  }

  revalidatePath('/clients'); revalidatePath('/dashboard')
  return { success: true, id: result.client_id }
}

// ── Update Client ─────────────────────────────────────────────────

export async function updateClientAction(id: string, formData: FormData) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  
  if (!orgId) return { error: 'No active organisation.' }

  const name = (formData.get('name') as string)?.trim()
  const gstin = (formData.get('gstin') as string)?.trim() || null
  const pan = (formData.get('pan') as string)?.trim() || null
  const idempotencyKey = (formData.get('idempotencyKey') as string)?.trim() || randomUUID()

  if (!name || name.length < 2) {
    return { error: 'Client name must be at least 2 characters.' }
  }

  const { data: activeClient } = await supabase
    .from('clients')
    .select('id, revision')
    .eq('id', id)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()
  if (!activeClient) return { error: 'Client not found or is read-only in Trash.' }

  const expectedRevisionValue = formData.get('expectedRevision')
  const requestedRevision = expectedRevisionValue === null
    ? activeClient.revision
    : Number(expectedRevisionValue)
  if (!Number.isSafeInteger(requestedRevision) || requestedRevision < 1) {
    return { error: 'Refresh this client before saving changes.' }
  }
  const { data: command, error: commandError } = await supabase.rpc('update_client_command', {
    p_client_id: id,
    p_expected_revision: requestedRevision,
    p_name: name,
    p_gstin: gstin ?? '',
    p_pan: pan ?? '',
    p_idempotency_key: idempotencyKey,
  })
  const result = command?.[0]
  if (commandError || !result || result.code !== 'ok') {
    console.error('Update client command error:', commandError ?? result?.code)
    const messages: Record<string, string> = {
      invalid_request: 'Check the client name, GSTIN, and PAN.',
      not_allowed: 'You do not have permission to update clients.',
      context_unavailable: 'Client not found or is read-only in Trash.',
      conflict: 'This client changed. Refresh before saving again.',
      identifier_conflict: 'An active client already uses this GSTIN or PAN.',
      idempotency_conflict: 'This submission key was already used for another request.',
    }
    return { error: messages[result?.code ?? ''] ?? 'Failed to update client.' }
  }

  revalidatePath('/clients'); revalidatePath('/dashboard')
  revalidatePath(`/clients/${id}`)
  return { success: true }
}

// ── Move Client hierarchy to Trash ─────────────────────────────────

export async function deleteClientAction(id: string, idempotencyKey = `trash.client.${crypto.randomUUID()}`) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const { data, error } = await supabase.rpc('trash_resource', {
    p_resource_type: 'client',
    p_resource_id: id,
    p_idempotency_key: idempotencyKey,
  })
  const result = data?.[0]

  if (error || !result) return { error: 'Could not move this client to Trash. Please try again.' }
  if (result.code === 'trashed' || result.code === 'already_trashed') {
    scheduleDocumentOutboxWake()
    revalidatePath('/clients'); revalidatePath('/dashboard')
    revalidatePath('/matters')
    return { success: true, operationId: result.operation_id, status: result.code }
  }
  if (result.code === 'not_allowed') return { error: 'You do not have permission to move this client to Trash.' }
  if (result.code === 'not_available') return { error: 'This client is no longer available.' }
  if (result.code === 'idempotency_conflict') return { error: 'This request key was already used for another resource.' }
  return { error: 'Could not move this client to Trash. Please try again.' }
}
