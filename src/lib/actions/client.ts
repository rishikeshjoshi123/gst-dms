'use server'

import { createClient } from '@/lib/supabase/server'
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

  // Check if admin (enforced by RLS anyway, but good for custom error)
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const { error } = await supabase
    .from('clients')
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', id)
    .eq('org_id', orgId)

  if (error) {
    console.error('Delete client error:', error)
    // Could be RLS policy violation if not admin
    return { error: 'Failed to delete client. Only admins can delete clients.' }
  }

  revalidatePath('/clients')
  return { success: true }
}
