'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'
import { appendActivity } from '@/lib/activity'

// ── Read Clients ──────────────────────────────────────────────────

export async function getClients() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data } = await supabase
    .from('clients')
    .select('*, matters(id, status)')
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .eq('matters.record_state', 'active')
    .is('matters.deleted_at', null)
    .order('name')

  if (!data) return []

  return data.map((client: any) => {
    const activeMatters = client.matters || []
    return {
      ...client,
      totalMatters: activeMatters.length,
      openMatters: activeMatters.filter((m: any) => m.status !== 'closed' && m.status !== 'disposed').length
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

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const name = (formData.get('name') as string)?.trim()
  const gstin = (formData.get('gstin') as string)?.trim() || null
  const pan = (formData.get('pan') as string)?.trim() || null

  if (!name || name.length < 2) {
    return { error: 'Client name must be at least 2 characters.' }
  }

  const db = createServiceClient()

  const { data, error } = await db
    .from('clients')
    .insert({
      org_id: orgId,
      name,
      gstin,
      pan,
    })
    .select('id')
    .single()

  if (error || !data) {
    console.error('Create client error:', error)
    return { error: error?.message ?? 'Failed to create client.' }
  }

  // Log activity
  await appendActivity({
    org_id: orgId,
    user_id: user.id,
    action: 'client_created',
    entity_type: 'client',
    entity_id: data.id,
    description: `Created client "${name}"`,
  })

  revalidatePath('/clients'); revalidatePath('/dashboard')
  return { success: true, id: data.id }
}

// ── Update Client ─────────────────────────────────────────────────

export async function updateClientAction(id: string, formData: FormData) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const name = (formData.get('name') as string)?.trim()
  const gstin = (formData.get('gstin') as string)?.trim() || null
  const pan = (formData.get('pan') as string)?.trim() || null

  if (!name || name.length < 2) {
    return { error: 'Client name must be at least 2 characters.' }
  }

  const db = createServiceClient()

  const { data: activeClient } = await supabase
    .from('clients')
    .select('id')
    .eq('id', id)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()
  if (!activeClient) return { error: 'Client not found or is read-only in Trash.' }

  const { data: updatedClient, error } = await db
    .from('clients')
    .update({
      name,
      gstin,
      pan,
      updated_at: new Date().toISOString(),
    })
    .eq('id', id)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .select('id')
    .maybeSingle()

  if (error) {
    console.error('Update client error:', error)
    return { error: error.message }
  }
  if (!updatedClient) return { error: 'Client not found or is read-only in Trash.' }

  // Log activity
  await db.from('activity_logs').insert({
    org_id: orgId,
    user_id: user.id,
    action: 'client_updated',
    entity_type: 'client',
    entity_id: id,
    description: `Updated client "${name}"`,
  })

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
    revalidatePath('/clients'); revalidatePath('/dashboard')
    revalidatePath('/matters')
    return { success: true, operationId: result.operation_id, status: result.code }
  }
  if (result.code === 'not_allowed') return { error: 'You do not have permission to move this client to Trash.' }
  if (result.code === 'not_available') return { error: 'This client is no longer available.' }
  if (result.code === 'idempotency_conflict') return { error: 'This request key was already used for another resource.' }
  return { error: 'Could not move this client to Trash. Please try again.' }
}
