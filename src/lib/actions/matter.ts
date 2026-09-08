'use server'

import { createClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { reevaluateMatterLinks } from './chaining'
import { revalidatePath } from 'next/cache'
import { generateDefaultMatterTitle } from '@/lib/utils/matterNaming'
import { scheduleDocumentOutboxWake } from '@/lib/outbox/wake'
import { randomUUID } from 'node:crypto'
import {
  escapeMatterDestinationLike,
  MATTER_DESTINATION_RESULT_LIMIT,
  normalizeMatterDestinationSearch,
  type MatterDestinationSearchOptions,
} from '@/lib/matter-destination-search'

// ── Types ─────────────────────────────────────────────────────────

import { FINANCIAL_YEARS } from '../constants'
import {
  normalizeMatterState,
  type MatterCurrentForum,
  type MatterWorkState,
} from '@/lib/matters/matter-state'

export type MatterDestinationOption = {
  id: string
  title: string | null
  matter_code: string | null
  financial_year: string | null
  clients: { name: string | null } | null
}

export type MatterDestinationSearchResult =
  | { ok: true; matters: MatterDestinationOption[] }
  | { ok: false; error: string }

const MATTER_DESTINATION_SELECT = 'id, title, matter_code, financial_year, clients(id, name)'

function uniqueMatterDestinations(rows: MatterDestinationOption[]) {
  return Array.from(new Map(rows.map((matter) => [matter.id, matter])).values())
}

export async function searchMatterDestinations(
  options: MatterDestinationSearchOptions = {},
): Promise<MatterDestinationSearchResult> {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { ok: false, error: 'No active organisation is available.' }
  const { query, includeIds } = normalizeMatterDestinationSearch(options)

  const includedRequest = includeIds.length > 0
    ? supabase
        .from('matters')
        .select(MATTER_DESTINATION_SELECT)
        .eq('org_id', orgId)
        .eq('record_state', 'active')
        .is('deleted_at', null)
        .in('id', includeIds)
    : Promise.resolve({ data: [], error: null })

  const baseQuery = () => supabase
    .from('matters')
    .select(MATTER_DESTINATION_SELECT)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
    .order('id', { ascending: true })
    .limit(MATTER_DESTINATION_RESULT_LIMIT)

  const matchRequests = query
    ? (() => {
        const pattern = `%${escapeMatterDestinationLike(query)}%`
        return [
          baseQuery().ilike('title', pattern),
          baseQuery().ilike('matter_code', pattern),
          baseQuery().ilike('financial_year', pattern),
          supabase
            .from('matters')
            .select('id, title, matter_code, financial_year, clients!inner(id, name)')
            .eq('org_id', orgId)
            .eq('record_state', 'active')
            .is('deleted_at', null)
            .ilike('clients.name', pattern)
            .order('created_at', { ascending: false })
            .order('id', { ascending: true })
            .limit(MATTER_DESTINATION_RESULT_LIMIT),
        ]
      })()
    : [baseQuery()]

  const [includedResult, ...matchResults] = await Promise.all([includedRequest, ...matchRequests])
  const failedResult = [includedResult, ...matchResults].find((result) => result.error)
  if (failedResult?.error) {
    console.error('Failed to search matter destinations:', failedResult.error)
    return { ok: false, error: 'Matter destinations could not be loaded.' }
  }

  const included = (includedResult.data ?? []) as unknown as MatterDestinationOption[]
  const matches = uniqueMatterDestinations(matchResults.flatMap((result) =>
    (result.data ?? []) as unknown as MatterDestinationOption[]))
    .slice(0, MATTER_DESTINATION_RESULT_LIMIT)

  return { ok: true, matters: uniqueMatterDestinations([...included, ...matches]) }
}

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

  return (data ?? []).map(normalizeMatterState)
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

  return (data ?? []).map(normalizeMatterState)
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

  return data ? normalizeMatterState(data) : null
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
  const workState = (formData.get('work_state') as MatterWorkState) || 'active'
  const currentForum = (formData.get('current_forum') as MatterCurrentForum) || 'adjudication'
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
    p_work_state: workState,
    p_current_forum: currentForum,
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
    description?: string | null
    workState?: MatterWorkState
    currentForum?: MatterCurrentForum
  },
  options: { expectedRevision?: number; idempotencyKey?: string } = {},
) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  if (payload.title !== undefined && payload.title.trim().length < 2) {
    return { error: 'Title must be at least 2 characters.' }
  }

  // Fetch current matter to get client_id for revalidation
  const { data: existingMatter } = await supabase
    .from('matters')
    .select('client_id, title, description, status, work_state, current_forum, revision')
    .eq('id', matterId)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()
  if (!existingMatter) return { error: 'Matter not found or is read-only in Trash.' }
  const currentMatter = normalizeMatterState(existingMatter)

  const expectedRevision = options.expectedRevision ?? existingMatter.revision
  if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 1) {
    return { error: 'Refresh this matter before saving changes.' }
  }
  const { data: command, error: commandError } = await supabase.rpc('update_matter_command', {
    p_matter_id: matterId,
    p_expected_revision: expectedRevision,
    p_title: payload.title?.trim() ?? existingMatter.title,
    p_description: payload.description === undefined
      ? (existingMatter.description ?? '')
      : (payload.description?.trim() ?? ''),
    p_work_state: payload.workState ?? currentMatter.work_state,
    p_current_forum: payload.currentForum ?? currentMatter.current_forum,
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

  revalidatePath('/matters'); revalidatePath('/dashboard')
  revalidatePath(`/matters/${matterId}`)
  if (existingMatter?.client_id) {
    revalidatePath(`/clients/${existingMatter.client_id}`)
  }
  return { success: true, revision: result.revision }
}

export async function updateMatter(id: string, formData: FormData) {
  const title = (formData.get('title') as string)?.trim()
  const description = (formData.get('description') as string)?.trim() || null
  const workState = formData.get('work_state') as MatterWorkState | null
  const currentForum = formData.get('current_forum') as MatterCurrentForum | null

  return updateMatterDetails(id, {
    title,
    description,
    ...(workState ? { workState } : {}),
    ...(currentForum ? { currentForum } : {}),
  })
}

// ── Archive / Close Matter ────────────────────────────────────────

export async function setMatterStatus(id: string, workState: MatterWorkState, currentForum?: MatterCurrentForum) {
  return updateMatterDetails(id, { workState, ...(currentForum ? { currentForum } : {}) })
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
