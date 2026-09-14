'use server'

import { cookies } from 'next/headers'
import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { sendOrgInviteEmail } from '@/lib/email'
import { randomUUID } from 'node:crypto'
import { createInvitationSelector, hashInvitationOpaqueValue } from '@/lib/invitations'
import { z } from 'zod'

// ── Helpers ──────────────────────────────────────────────────────

async function setCurrentOrg(orgId: string) {
  const cookieStore = await cookies()
  cookieStore.set('current_org_id', orgId, {
    httpOnly: true,
    path: '/',
    maxAge: 60 * 60 * 24 * 365,
    sameSite: 'lax',
  })
}

export async function getCurrentOrgId(): Promise<string | null> {
  const cookieStore = await cookies()
  const orgId = cookieStore.get('current_org_id')?.value

  // The cookie is only a UI preference, never an authorization grant.
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return null

  if (orgId) {
    const { data } = await supabase.rpc('get_my_organisation_context')
    const membership = (data ?? []).find((row: { org_id: string; state: string }) => row.org_id === orgId && row.state === 'active')
    if (membership) return membership.org_id
  }

  // A preference can be absent or stale (for example, an older session). Use
  // a verified membership for this request; a later sign-in/org switch writes
  // the preference from a Server Action.
  const { data } = await supabase.rpc('get_my_organisation_context')
  return ((data ?? []).find((row: { state: string }) => row.state === 'active') as { org_id?: string } | undefined)?.org_id ?? null
}

const invitationError = (code?: string) => {
  if (code === 'rate_limited') return 'Invitation sending is temporarily limited. Please try again later.'
  if (code === 'pending_exists') return 'A pending invitation already exists for this address.'
  if (code === 'not_available') return 'This invitation is not available.'
  if (code === 'conflict') return 'This invitation changed. Refresh and try again.'
  if (code === 'idempotency_subject_mismatch') return 'This request could not be retried safely. Refresh and try again.'
  if (code === 'invalid_request') return 'Check the invitation details and try again.'
  return 'You do not have permission to complete this invitation action.'
}

const emailSchema = z.string().trim().toLowerCase().email().max(320)
const idempotencySchema = z.string().uuid()

// ── Create Organisation ───────────────────────────────────────────

export async function createOrganisation(formData: FormData) {
  const name = String(formData.get('name') ?? '').trim()
  const idempotencyKey = String(formData.get('idempotency_key') ?? '')
  if (name.length<2 || name.length>200 || /[\u0000-\u001f\u007f]/.test(name)) {
    return { error: 'Enter an organisation name between 2 and 200 characters.' }
  }
  if (!z.string().uuid().safeParse(idempotencyKey).success) {
    return { error: 'Refresh this page before creating an organisation.' }
  }
  const supabase = await createClient()
  const { data,error } = await supabase.rpc('create_organisation', {
    p_name: name,
    p_idempotency_key: idempotencyKey,
  })
  const result = data?.[0]
  if (error || !result || result.code!=='ok' || !result.org_id) {
    return { error: 'The organisation could not be created. Refresh and try again.' }
  }
  await setCurrentOrg(result.org_id)
  redirect('/dashboard')
}

// ── Switch Organisation ───────────────────────────────────────────

export async function switchOrganisation(orgId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { data: contexts } = await supabase.rpc('get_my_organisation_context')
  if (!(contexts ?? []).some((context: { org_id: string; state: string }) => context.org_id === orgId && context.state === 'active')) return { error: 'Access denied.' }

  await setCurrentOrg(orgId)
  redirect('/dashboard')
}

// ── Invite Member ─────────────────────────────────────────────────

export async function inviteMember(formData: FormData) {
  const supabase = await createClient()
  const parsedEmail = emailSchema.safeParse(formData.get('email'))
  const role = String(formData.get('role') ?? '')
  const parsedIdempotency = idempotencySchema.safeParse(formData.get('idempotency_key'))
  if (!parsedEmail.success || !['admin', 'associate', 'viewer'].includes(role) || !parsedIdempotency.success) {
    return { error: 'Enter a valid email address and choose an available role.' }
  }
  const email = parsedEmail.data
  const selector = createInvitationSelector()
  const { data, error } = await supabase.rpc('create_organisation_invite', { p_email: email, p_role: role as 'admin' | 'associate' | 'viewer', p_selector_hash: hashInvitationOpaqueValue(selector), p_idempotency_key: parsedIdempotency.data })
  const result = data?.[0]
  if (error || !result || !['created', 'already_processed'].includes(result.code)) return { error: invitationError(result?.code) }
  if (result.code === 'already_processed') {
    revalidatePath('/team')
    return { error: 'This invitation request was already processed. Refresh Team and use the visible Resend action if delivery is not confirmed.' }
  }
  const delivery = await sendOrgInviteEmail({ to: email, orgName: result.org_name, inviterName: result.inviter_name, inviteUrl: `${process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'}/api/invites/accept?token=${encodeURIComponent(selector)}` })
  const { data: deliveryRows, error: deliveryRecordError } = await supabase.rpc('record_organisation_invite_delivery', { p_invite_id: result.invite_id, p_state: delivery.success ? 'sent' : 'failed', p_provider_reference: delivery.id ?? 'delivery-unavailable', p_error_code: delivery.success ? undefined : 'delivery_failed' })
  const deliveryRecordCode=deliveryRows?.[0]?.code
  revalidatePath('/team')
  if (deliveryRecordError || !['ok','already_processed'].includes(deliveryRecordCode ?? '')) return { error: 'The invitation was created, but its delivery status could not be recorded. Refresh Team before trying again.' }
  return delivery.success ? { success: true, replayed: false } : { error: 'The invitation was created, but email delivery failed. Resend it from Team.' }
}

// ── Get Pending Invites For User (Onboarding) ─────────────────────

export async function getMyPendingInvites() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return []
  const { data } = await supabase.rpc('get_my_pending_organisation_invites')
  return (data ?? []).map((invite: { id: string; role: string; org_name: string }) => ({ id: invite.id, role: invite.role, orgName: invite.org_name }))
}

// ── Accept / Reject Invite (Tokenless) ────────────────────────────

export async function acceptInvite(inviteId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'You must be logged in to accept an invitation.' }
  const { data } = await supabase.rpc('accept_organisation_invite', { p_invite_id: inviteId, p_idempotency_key: randomUUID() })
  const result = data?.[0]
  if (!result || result.code !== 'accepted') return { error: invitationError(result?.code) }
  await setCurrentOrg(result.org_id)
  redirect('/dashboard')
}

export async function rejectInvite(inviteId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not logged in.' }
  const { data: rows } = await supabase.rpc('get_my_pending_organisation_invites')
  const invite = rows?.find((row: { id: string }) => row.id === inviteId)
  if (!invite) return { error: 'This invitation is not available.' }
  const { data } = await supabase.rpc('transition_organisation_invite', { p_invite_id: inviteId, p_expected_revision: invite.revision, p_idempotency_key: randomUUID(), p_action: 'reject' })
  return data?.[0]?.code === 'ok' ? { success: true } : { error: invitationError(data?.[0]?.code) }
}

// ── Get user's organisations ──────────────────────────────────────

export async function getUserOrgs() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return []

  const { data } = await supabase.rpc('get_my_organisation_context')
  const contexts = (data ?? []).filter((m: { state: string }) => m.state === 'active') as Array<{ org_id: string; role: string }>
  const organisations = await Promise.all(contexts.map(async (context) => {
    const { data: org } = await supabase.from('organisations').select('id, name, created_at').eq('id', context.org_id).maybeSingle()
    return org ? { ...org, role: context.role } : null
  }))
  return organisations.filter(Boolean)
}

// ── Admin: Get Pending Invites for Settings ───────────────────────

export async function getPendingInvitesForOrg() {
  const supabase = await createClient()
  const { data } = await supabase.rpc('get_organisation_invites', { p_state: 'pending' })
  return data ?? []
}

export async function revokeInvite(inviteId: string, expectedRevision: number, idempotencyKey: string) {
  if (!z.string().uuid().safeParse(inviteId).success || !Number.isSafeInteger(expectedRevision) || expectedRevision < 1 || !idempotencySchema.safeParse(idempotencyKey).success) {
    return { error: 'This invitation action is invalid. Refresh and try again.' }
  }
  const supabase = await createClient()
  const { data } = await supabase.rpc('transition_organisation_invite', { p_invite_id: inviteId, p_expected_revision: expectedRevision, p_idempotency_key: idempotencyKey, p_action: 'revoke', p_reason: 'Revoked by an administrator' })
  if (data?.[0]?.code !== 'ok') return { error: invitationError(data?.[0]?.code) }
  revalidatePath('/team')
  return { success: true }
}

/** @deprecated Team owns invitation administration; use revokeInvite. */
export const deleteInvite = revokeInvite

export async function resendInvite(inviteId: string, expectedRevision: number, idempotencyKey: string) {
  if (!z.string().uuid().safeParse(inviteId).success || !Number.isSafeInteger(expectedRevision) || expectedRevision < 1 || !idempotencySchema.safeParse(idempotencyKey).success) {
    return { error: 'This invitation action is invalid. Refresh and try again.' }
  }
  const supabase = await createClient()
  const { data: rows } = await supabase.rpc('get_organisation_invites', { p_state: 'pending' })
  const previous = rows?.find((row: { id: string }) => row.id === inviteId)
  if (!previous) return { error: 'This invitation is not available.' }
  const selector = createInvitationSelector()
  const { data } = await supabase.rpc('resend_organisation_invite', { p_invite_id: inviteId, p_expected_revision: expectedRevision, p_selector_hash: hashInvitationOpaqueValue(selector), p_idempotency_key: idempotencyKey })
  const result = data?.[0]
  if (!result || !['created', 'already_processed'].includes(result.code)) return { error: invitationError(result?.code) }
  if (result.code === 'already_processed') {
    revalidatePath('/team')
    return { error: 'This resend request was already processed. Refresh Team and use the visible Resend action if delivery is not confirmed.' }
  }
  const delivery = await sendOrgInviteEmail({ to: previous.authorized_email, orgName: result.org_name, inviterName: result.inviter_name, inviteUrl: `${process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'}/api/invites/accept?token=${encodeURIComponent(selector)}` })
  const { data: deliveryRows, error: deliveryRecordError } = await supabase.rpc('record_organisation_invite_delivery', { p_invite_id: result.invite_id, p_state: delivery.success ? 'sent' : 'failed', p_provider_reference: delivery.id ?? 'delivery-unavailable', p_error_code: delivery.success ? undefined : 'delivery_failed' })
  const deliveryRecordCode=deliveryRows?.[0]?.code
  revalidatePath('/team')
  if (deliveryRecordError || !['ok','already_processed'].includes(deliveryRecordCode ?? '')) return { error: 'The invitation was renewed, but its delivery status could not be recorded. Refresh Team before trying again.' }
  return delivery.success ? { success: true, replayed: false } : { error: 'The invitation was renewed, but email delivery failed. Try resending again later.' }
}
