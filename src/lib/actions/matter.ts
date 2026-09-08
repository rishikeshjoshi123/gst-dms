'use server'

import { createClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { reevaluateMatterLinks } from './chaining'
import { revalidatePath } from 'next/cache'
import { generateDefaultMatterTitle } from '@/lib/utils/matterNaming'
import { scheduleDocumentOutboxWake } from '@/lib/outbox/wake'
import { canonicalDocumentPath } from '@/lib/canonical-document-route'
import { randomUUID } from 'node:crypto'

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
    .eq('record_state', 'active')
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
    .eq('record_state', 'active')
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
  const idempotencyKey = (formData.get('idempotencyKey') as string)?.trim() || randomUUID()

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
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()

  if (!client) return { error: 'Client not found.' }

  let finalTitle = title
  if (!finalTitle) {
    finalTitle = await generateDefaultMatterTitle(supabase, orgId, clientId, client.name, financialYear)
  }

  const { data: command, error: commandError } = await supabase.rpc('create_matter_command', {
    p_client_id: clientId,
    p_title: finalTitle,
    p_financial_year: financialYear,
    p_description: description ?? '',
    p_status: status,
    p_idempotency_key: idempotencyKey,
  })
  const result = command?.[0]
  if (commandError || !result || result.code !== 'ok' || !result.matter_id) {
    console.error('Create matter command error:', commandError ?? result?.code)
    const messages: Record<string, string> = {
      invalid_request: 'Check the matter title, financial year, and description.',
      not_allowed: 'You do not have permission to create matters.',
      context_unavailable: 'The selected client is no longer active.',
      identifier_conflict: 'An active matter already uses this client and financial year, or its code conflicted. Choose another year or try again.',
      idempotency_conflict: 'This submission key was already used for another request.',
    }
    return { error: messages[result?.code ?? ''] ?? 'Failed to create matter.' }
  }

  revalidatePath('/matters'); revalidatePath('/dashboard')
  revalidatePath(`/clients/${clientId}`)
  return { success: true, id: result.matter_id }
}

// ── Update Matter ─────────────────────────────────────────────────

export async function updateMatterDetails(
  matterId: string,
  payload: {
    title?: string
    financialYear?: string
    description?: string | null
    status?: MatterStatus
  },
  options: { expectedRevision?: number; idempotencyKey?: string } = {},
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
    .select('client_id, title, financial_year, description, status, revision')
    .eq('id', matterId)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()
  if (!existingMatter) return { error: 'Matter not found or is read-only in Trash.' }

  const expectedRevision = options.expectedRevision ?? existingMatter.revision
  if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 1) {
    return { error: 'Refresh this matter before saving changes.' }
  }
  const financialYear = payload.financialYear ?? existingMatter.financial_year
  const { data: command, error: commandError } = await supabase.rpc('update_matter_command', {
    p_matter_id: matterId,
    p_expected_revision: expectedRevision,
    p_title: payload.title?.trim() ?? existingMatter.title,
    p_financial_year: financialYear,
    p_description: payload.description === undefined
      ? (existingMatter.description ?? '')
      : (payload.description?.trim() ?? ''),
    p_status: payload.status ?? existingMatter.status,
    p_idempotency_key: options.idempotencyKey ?? randomUUID(),
  })
  const result = command?.[0]
  if (commandError || !result || result.code !== 'ok') {
    console.error('Update matter command error:', commandError ?? result?.code)
    const messages: Record<string, string> = {
      invalid_request: 'Check the matter title, financial year, and description.',
      not_allowed: 'You do not have permission to update matters.',
      context_unavailable: 'Matter not found or is read-only in Trash.',
      conflict: 'This matter changed. Refresh before saving again.',
      idempotency_conflict: 'This submission key was already used for another request.',
    }
    return { error: messages[result?.code ?? ''] ?? 'Failed to update matter.' }
  }

  if (payload.financialYear && payload.financialYear !== 'Unknown FY') {
    const { data: updatedDocuments } = await supabase
      .from('documents')
      .select('id')
      .eq('matter_id', matterId)
      .eq('org_id', orgId)
      .eq('record_state', 'active')
      .is('deleted_at', null)
      .eq('financial_year', payload.financialYear)

    for (const document of updatedDocuments ?? []) revalidatePath(canonicalDocumentPath(document.id))
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
  return updateMatterDetails(id, { status })
}


export async function autoLinkUnlinkedDocuments(matterId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const res = await reevaluateMatterLinks(supabase, matterId, orgId, user.id)
  
  revalidatePath(`/matters/${matterId}`)
  
  return res
}


export async function updateMatterTitle(matterId: string, newTitle: string) {
  return updateMatterDetails(matterId, { title: newTitle })
}

export async function deleteMatterAction(matterId: string, idempotencyKey = `trash.matter.${crypto.randomUUID()}`) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { data, error } = await supabase.rpc('trash_resource', {
    p_resource_type: 'matter',
    p_resource_id: matterId,
    p_idempotency_key: idempotencyKey,
  })
  const result = data?.[0]

  if (error || !result) return { error: 'Could not move this matter to Trash. Please try again.' }
  if (result.code === 'trashed' || result.code === 'already_trashed') {
    scheduleDocumentOutboxWake()
    revalidatePath('/matters'); revalidatePath('/dashboard')
    return { success: true, operationId: result.operation_id, status: result.code }
  }
  if (result.code === 'not_allowed') return { error: 'You do not have permission to move this matter to Trash.' }
  if (result.code === 'not_available') return { error: 'This matter is no longer available.' }
  if (result.code === 'idempotency_conflict') return { error: 'This request key was already used for another resource.' }
  return { error: 'Could not move this matter to Trash. Please try again.' }
}
