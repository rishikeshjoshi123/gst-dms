'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'

// ── Read Clients ──────────────────────────────────────────────────

export async function getClients() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data } = await supabase
    .from('clients')
    .select('*, matters(id, status)')
    .eq('org_id', orgId)
    .is('deleted_at', null)
    .order('name')

  // Calculate counts for UI
  const clientsWithCounts = (data ?? []).map(client => {
    const matters = client.matters ?? []
    return {
      ...client,
      totalMatters: matters.length,
      openMatters: matters.filter(m => m.status === 'active' || m.status === 'appeal_pending' || m.status === 'high_court' || m.status === 'supreme_court' || m.status === 'stayed' || m.status === 'tribunal').length
    }
  })

  return clientsWithCounts
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

  if (!name || name.length < 2) {
    return { error: 'Client name must be at least 2 characters.' }
  }

  const { data, error } = await supabase
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

  revalidatePath('/clients')
  return { success: true, id: data.id }
}

// ── Update Client ─────────────────────────────────────────────────

export async function updateClientAction(id: string, formData: FormData) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  
  if (!orgId) return { error: 'No active organisation.' }

  const name = (formData.get('name') as string)?.trim()
  const gstin = (formData.get('gstin') as string)?.trim() || null
  const pan = (formData.get('pan') as string)?.trim() || null

  if (!name || name.length < 2) {
    return { error: 'Client name must be at least 2 characters.' }
  }

  const { error } = await supabase
    .from('clients')
    .update({
      name,
      gstin,
      pan,
      updated_at: new Date().toISOString(),
    })
    .eq('id', id)
    .eq('org_id', orgId)

  if (error) {
    console.error('Update client error:', error)
    return { error: error.message }
  }

  revalidatePath('/clients')
  revalidatePath(`/clients/${id}`)
  return { success: true }
}

// ── Soft Delete Client ────────────────────────────────────────────

export async function deleteClientAction(id: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const nowStr = new Date().toISOString()
  const db = createServiceClient()

  // 1. Get client's matters
  const { data: matters } = await db
    .from('matters')
    .select('id')
    .eq('client_id', id)
    .eq('org_id', orgId)

  const matterIds = (matters || []).map(m => m.id)

  // 2. Soft delete associated documents
  if (matterIds.length > 0) {
    await db
      .from('documents')
      .update({ deleted_at: nowStr })
      .in('matter_id', matterIds)
      .eq('org_id', orgId)

    // 3. Soft delete associated case notes
    await db
      .from('case_notes')
      .update({ deleted_at: nowStr })
      .in('matter_id', matterIds)
      .eq('org_id', orgId)

    // 4. Soft delete associated matters
    await db
      .from('matters')
      .update({ deleted_at: nowStr })
      .in('id', matterIds)
      .eq('org_id', orgId)
  }

  // 5. Soft delete client
  const { error } = await db
    .from('clients')
    .update({ deleted_at: nowStr })
    .eq('id', id)
    .eq('org_id', orgId)

  if (error) {
    console.error('Delete client error:', error)
    return { error: 'Failed to delete client.' }
  }

  revalidatePath('/clients')
  revalidatePath('/matters')
  return { success: true }
}
