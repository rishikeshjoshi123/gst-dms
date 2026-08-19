'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { reevaluateMatterLinks } from './chaining'
import { revalidatePath } from 'next/cache'
import { generateDefaultMatterTitle } from '@/lib/utils/matterNaming'

// ── Types ─────────────────────────────────────────────────────────

import { MatterStatus, FINANCIAL_YEARS } from '../constants'

// ── Read Matters ──────────────────────────────────────────────────

export async function getMatters() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data } = await supabase
    .from('matters')
    .select(`
      *,
      clients(id, name, gstin)
    `)
    .eq('org_id', orgId)
    .is('deleted_at', null)
    .order('created_at', { ascending: false })

  return data ?? []
}

export async function getMattersByClient(clientId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data } = await supabase
    .from('matters')
    .select('*')
    .eq('org_id', orgId)
    .eq('client_id', clientId)
    .is('deleted_at', null)
    .order('created_at', { ascending: false })

  return data ?? []
}

export async function getMatterById(id: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return null

  const { data } = await supabase
    .from('matters')
    .select(`
      *,
      clients(id, name, gstin, pan)
    `)
    .eq('id', id)
    .eq('org_id', orgId)
    .is('deleted_at', null)
    .single()

  return data
}

// ── Create Matter ─────────────────────────────────────────────────

export async function createMatter(formData: FormData) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const clientId = formData.get('client_id') as string
  const title = (formData.get('title') as string)?.trim()
  const financialYear = formData.get('financial_year') as string
  const description = (formData.get('description') as string)?.trim() || null
  const status = (formData.get('status') as MatterStatus) || 'active'

  if (!clientId) return { error: 'Client is required.' }
  if (!financialYear) return { error: 'Financial year is required.' }
  if (!FINANCIAL_YEARS.includes(financialYear)) {
    return { error: 'Please select a valid financial year.' }
  }

  // Verify client belongs to this org
  const { data: client } = await supabase
    .from('clients')
    .select('id, name')
    .eq('id', clientId)
    .eq('org_id', orgId)
    .single()

  if (!client) return { error: 'Client not found.' }

  let finalTitle = title
  if (!finalTitle) {
    finalTitle = await generateDefaultMatterTitle(supabase, orgId, clientId, client.name, financialYear)
  }

  const { data, error } = await supabase
    .from('matters')
    .insert({
      org_id: orgId,
      client_id: clientId,
      title: finalTitle,
      financial_year: financialYear,
      description,
      status,
    })
    .select('id, matter_code')
    .single()

  if (error || !data) {
    console.error('Create matter error:', error)
    return { error: error?.message ?? 'Failed to create matter.' }
  }

  revalidatePath('/matters'); revalidatePath('/dashboard')
  revalidatePath(`/clients/${clientId}`)
  return { success: true, id: data.id, matterCode: data.matter_code }
}

// ── Update Matter ─────────────────────────────────────────────────

export async function updateMatterDetails(
  matterId: string,
  payload: {
    title?: string
    financialYear?: string
    description?: string | null
    status?: MatterStatus
  }
) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  if (payload.title !== undefined && payload.title.trim().length < 2) {
    return { error: 'Title must be at least 2 characters.' }
  }

  if (payload.financialYear !== undefined && payload.financialYear !== 'Unknown FY') {
    if (!FINANCIAL_YEARS.includes(payload.financialYear)) {
      return { error: 'Invalid financial year selected.' }
    }
  }

  // Fetch current matter to get client_id for revalidation
  const { data: existingMatter } = await supabase
    .from('matters')
    .select('client_id')
    .eq('id', matterId)
    .eq('org_id', orgId)
    .single()

  const updateFields: any = {}
  if (payload.title !== undefined) updateFields.title = payload.title.trim()
  if (payload.financialYear !== undefined) updateFields.financial_year = payload.financialYear
  if (payload.description !== undefined) updateFields.description = payload.description?.trim() || null
  if (payload.status !== undefined) updateFields.status = payload.status

  const { error } = await supabase
    .from('matters')
    .update(updateFields)
    .eq('id', matterId)
    .eq('org_id', orgId)

  if (error) {
    console.error('Update matter error:', error)
    return { error: error.message }
  }

  // If financial year was updated, synchronize documents with 'Unknown FY' or missing FY
  if (payload.financialYear && payload.financialYear !== 'Unknown FY') {
    await supabase
      .from('documents')
      .update({ financial_year: payload.financialYear })
      .eq('matter_id', matterId)
      .eq('org_id', orgId)
      .or(`financial_year.eq.Unknown FY,financial_year.is.null`)
  }

  revalidatePath('/matters'); revalidatePath('/dashboard')
  revalidatePath(`/matters/${matterId}`)
  if (existingMatter?.client_id) {
    revalidatePath(`/clients/${existingMatter.client_id}`)
  }
  return { success: true }
}

export async function updateMatter(id: string, formData: FormData) {
  const title = (formData.get('title') as string)?.trim()
  const description = (formData.get('description') as string)?.trim() || null
  const status = formData.get('status') as MatterStatus | null

  return updateMatterDetails(id, {
    title,
    description,
    ...(status ? { status } : {})
  })
}

// ── Archive / Close Matter ────────────────────────────────────────

export async function setMatterStatus(id: string, status: MatterStatus) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { error } = await supabase
    .from('matters')
    .update({ status })
    .eq('id', id)
    .eq('org_id', orgId)

  if (error) {
    console.error('Set matter status error:', error)
    return { error: error.message }
  }

  revalidatePath('/matters'); revalidatePath('/dashboard')
  revalidatePath(`/matters/${id}`)
  return { success: true }
}


export async function autoLinkUnlinkedDocuments(matterId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const res = await reevaluateMatterLinks(supabase, matterId, orgId, user.id)
  
  const { revalidatePath } = require('next/cache')
  revalidatePath(`/matters/${matterId}`)
  
  return res
}


export async function updateMatterTitle(matterId: string, newTitle: string) {
  return updateMatterDetails(matterId, { title: newTitle })
}

export async function deleteMatterAction(matterId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const db = createServiceClient()

  const { data: matter } = await db
    .from('matters')
    .select('id, client_id, title')
    .eq('id', matterId)
    .eq('org_id', orgId)
    .single()

  if (!matter) return { error: 'Matter not found.' }

  const nowStr = new Date().toISOString()

  // 1. Soft delete all documents in this matter
  await db
    .from('documents')
    .update({ deleted_at: nowStr })
    .eq('matter_id', matterId)
    .eq('org_id', orgId)

  // 2. Soft delete case notes in this matter
  await db
    .from('case_notes')
    .update({ deleted_at: nowStr })
    .eq('matter_id', matterId)
    .eq('org_id', orgId)

  // 3. Delete wiki sections in this matter
  await db
    .from('wiki_sections')
    .delete()
    .eq('matter_id', matterId)

  // 3b. Un-suggest staged documents waiting for this matter
  await db
    .from('staged_documents')
    .update({ suggested_matter_id: null, suggested_matter_ids: [], suggestion_reason: 'Previously suggested matter was deleted.' })
    .eq('status', 'ready_to_assign')
    .eq('suggested_matter_id', matterId)
    .eq('org_id', orgId)

  // 4. Soft delete the matter
  const { error } = await db
    .from('matters')
    .update({ deleted_at: nowStr })
    .eq('id', matterId)
    .eq('org_id', orgId)

  if (error) {
    console.error('Delete matter error:', error)
    return { error: error.message }
  }

  // 5. Log activity
  await db.from('activity_logs').insert({
    org_id: orgId,
    user_id: user.id,
    action: 'matter_deleted',
    entity_type: 'matter',
    entity_id: matterId,
    description: `Deleted matter "${matter.title}"`,
    metadata: { client_id: matter.client_id }
  })

  revalidatePath('/matters'); revalidatePath('/dashboard')
  if (matter.client_id) {
    revalidatePath(`/clients/${matter.client_id}`)
  }

  return { success: true }
}
