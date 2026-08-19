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
  await db.from('activity_logs').insert({
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

  const { error } = await db
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

// ── Soft Delete Client ────────────────────────────────────────────

export async function deleteClientAction(id: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const nowStr = new Date().toISOString()
  const db = createServiceClient()

  // Fetch client details for logging
  const { data: client } = await db
    .from('clients')
    .select('name')
    .eq('id', id)
    .eq('org_id', orgId)
    .single()

  const clientName = client?.name || 'Client'

  // 1. Get client's matters
  const { data: matters } = await db
    .from('matters')
    .select('id')
    .eq('client_id', id)
    .eq('org_id', orgId)

  const matterIds = (matters || []).map((m: any) => m.id)

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

    // 4b. Un-suggest staged documents waiting for these matters
    await db
      .from('staged_documents')
      .update({ suggested_matter_id: null, suggested_matter_ids: [], suggestion_reason: 'Previously suggested matter was deleted.' })
      .eq('status', 'ready_to_assign')
      .in('suggested_matter_id', matterIds)
      .eq('org_id', orgId)
  }

  // 4c. Un-suggest staged documents waiting for this client
  await db
    .from('staged_documents')
    .update({ suggested_client_id: null, suggested_matter_id: null, suggested_matter_ids: [], suggestion_reason: 'Previously suggested client was deleted.' })
    .eq('status', 'ready_to_assign')
    .eq('suggested_client_id', id)
    .eq('org_id', orgId)

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

  // 6. Log activity
  await db.from('activity_logs').insert({
    org_id: orgId,
    user_id: user.id,
    action: 'client_deleted',
    entity_type: 'client',
    entity_id: id,
    description: `Deleted client "${clientName}"`,
    is_reversible: true
  })

  revalidatePath('/clients'); revalidatePath('/dashboard')
  revalidatePath('/matters')
  return { success: true }
}
