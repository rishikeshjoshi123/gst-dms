'use server'

import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { sendOrgInviteEmail } from '@/lib/email'
import { randomUUID } from 'node:crypto'
import { createInvitationSelector, hashInvitationOpaqueValue } from '@/lib/invitations'

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
    const { data } = await (supabase.rpc as any)('get_my_organisation_context')
    const membership = (data ?? []).find((row: { org_id: string; state: string }) => row.org_id === orgId && row.state === 'active')
    if (membership) return membership.org_id
  }

  // A preference can be absent or stale (for example, an older session). Use
  // a verified membership for this request; a later sign-in/org switch writes
  // the preference from a Server Action.
  const { data } = await (supabase.rpc as any)('get_my_organisation_context')
  return ((data ?? []).find((row: { state: string }) => row.state === 'active') as { org_id?: string } | undefined)?.org_id ?? null
}

const invitationError = (code?: string) => {
  if (code === 'rate_limited') return 'Please wait before sending another invitation.'
  if (code === 'pending_exists') return 'A pending invitation already exists for this address.'
  if (code === 'not_available') return 'This invitation is not available.'
  if (code === 'conflict') return 'This invitation changed. Refresh and try again.'
  return 'You do not have permission to complete this invitation action.'
}

// ── Create Organisation ───────────────────────────────────────────

export async function createOrganisation(formData: FormData) {
  const supabase = await createClient()
  const name = (formData.get('name') as string)?.trim()

  if (!name || name.length < 2) {
    return { error: 'Organisation name must be at least 2 characters.' }
  }

  const { data: { user }, error: userErr } = await supabase.auth.getUser()
  if (userErr || !user) return { error: 'Not authenticated.' }

  const { data: org, error: orgErr } = await supabase
    .from('organisations')
    .insert({ name, created_by: user.id })
    .select('id')
    .single()

  if (orgErr || !org) {
    return { error: 'Unable to create an organisation at this time.' }
  }

  await setCurrentOrg(org.id)
  redirect('/dashboard')
}

// ── Switch Organisation ───────────────────────────────────────────

export async function switchOrganisation(orgId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { data: contexts } = await (supabase.rpc as any)('get_my_organisation_context')
  if (!(contexts ?? []).some((context: { org_id: string; state: string }) => context.org_id === orgId && context.state === 'active')) return { error: 'Access denied.' }

  await setCurrentOrg(orgId)
  redirect('/dashboard')
}

// ── Invite Member ─────────────────────────────────────────────────

export async function inviteMember(formData: FormData) {
  const supabase = await createClient()
  const email = (formData.get('email') as string | null)?.trim().toLowerCase() ?? ''
  const role = formData.get('role')
  if (!email || !['admin', 'associate', 'viewer'].includes(String(role))) return { error: 'Enter a valid email address and role.' }
  const selector = createInvitationSelector()
  const { data, error } = await (supabase.rpc as any)('create_organisation_invite', { p_email: email, p_role: role, p_selector_hash: hashInvitationOpaqueValue(selector), p_idempotency_key: randomUUID() })
  const result = data?.[0]
  if (error || !result || result.code !== 'created') return { error: invitationError(result?.code) }
  const delivery = await sendOrgInviteEmail({ to: email, orgName: result.org_name, inviterName: result.inviter_name, inviteUrl: `${process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'}/api/invites/accept?token=${encodeURIComponent(selector)}` })
  await (supabase.rpc as any)('record_organisation_invite_delivery', { p_invite_id: result.invite_id, p_state: delivery.success ? 'sent' : 'failed', p_provider_reference: delivery.id ?? 'delivery-unavailable', p_error_code: delivery.success ? null : 'delivery_failed' })
  return { success: true }
}

// ── Get Pending Invites For User (Onboarding) ─────────────────────

export async function getMyPendingInvites() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return []
  const { data } = await (supabase.rpc as any)('get_my_pending_organisation_invites')
  return (data ?? []).map((invite: { id: string; role: string; org_name: string }) => ({ id: invite.id, role: invite.role, orgName: invite.org_name }))
}

// ── Accept / Reject Invite (Tokenless) ────────────────────────────

export async function acceptInvite(inviteId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'You must be logged in to accept an invitation.' }
  const { data } = await (supabase.rpc as any)('accept_organisation_invite', { p_invite_id: inviteId, p_idempotency_key: randomUUID() })
  const result = data?.[0]
  if (!result || result.code !== 'accepted') return { error: invitationError(result?.code) }
  await setCurrentOrg(result.org_id)
  redirect('/dashboard')
}

export async function rejectInvite(inviteId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not logged in.' }
  const { data: rows } = await (supabase.rpc as any)('get_my_pending_organisation_invites')
  const invite = rows?.find((row: { id: string }) => row.id === inviteId)
  if (!invite) return { error: 'This invitation is not available.' }
  const { data } = await (supabase.rpc as any)('transition_organisation_invite', { p_invite_id: inviteId, p_expected_revision: invite.revision, p_idempotency_key: randomUUID(), p_action: 'reject', p_reason: null })
  return data?.[0]?.code === 'ok' ? { success: true } : { error: invitationError(data?.[0]?.code) }
}

// ── Get user's organisations ──────────────────────────────────────

export async function getUserOrgs() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return []

  const { data } = await (supabase.rpc as any)('get_my_organisation_context')
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
  const { data } = await (supabase.rpc as any)('get_organisation_invites')
  return data ?? []
}

export async function deleteInvite(inviteId: string) {
  const supabase = await createClient()
  const { data: rows } = await (supabase.rpc as any)('get_organisation_invites')
  const invite = rows?.find((row: { id: string }) => row.id === inviteId)
  if (!invite) return { error: 'This invitation is not available.' }
  const { data } = await (supabase.rpc as any)('transition_organisation_invite', { p_invite_id: inviteId, p_expected_revision: invite.revision, p_idempotency_key: randomUUID(), p_action: 'revoke', p_reason: 'Revoked by an administrator' })
  return data?.[0]?.code === 'ok' ? { success: true } : { error: invitationError(data?.[0]?.code) }
}

export async function resendInvite(inviteId: string) {
  const supabase = await createClient()
  const { data: rows } = await (supabase.rpc as any)('get_organisation_invites')
  const previous = rows?.find((row: { id: string }) => row.id === inviteId)
  if (!previous) return { error: 'This invitation is not available.' }
  const selector = createInvitationSelector()
  const { data } = await (supabase.rpc as any)('resend_organisation_invite', { p_invite_id: inviteId, p_expected_revision: previous.revision, p_selector_hash: hashInvitationOpaqueValue(selector), p_idempotency_key: randomUUID() })
  const result = data?.[0]
  if (!result || result.code !== 'created') return { error: invitationError(result?.code) }
  const delivery = await sendOrgInviteEmail({ to: previous.authorized_email, orgName: result.org_name, inviterName: result.inviter_name, inviteUrl: `${process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'}/api/invites/accept?token=${encodeURIComponent(selector)}` })
  await (supabase.rpc as any)('record_organisation_invite_delivery', { p_invite_id: result.invite_id, p_state: delivery.success ? 'sent' : 'failed', p_provider_reference: delivery.id ?? 'delivery-unavailable', p_error_code: delivery.success ? null : 'delivery_failed' })
  return { success: true }
}

// ── Admin: Remove Member (Kickout Flow) ───────────────────────────

export async function removeMember(userIdToRemove: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active org.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { createServiceClient } = await import('@/lib/supabase/server')
  const supabaseAdmin = createServiceClient()

  // Get caller's role, org details, and target member via admin client
  const [{ data: caller }, { data: org }, { data: target }] = await Promise.all([
    supabaseAdmin.from('org_members').select('role').eq('org_id', orgId).eq('user_id', user.id).single(),
    supabaseAdmin.from('organisations').select('created_by').eq('id', orgId).single(),
    supabaseAdmin.from('org_members').select('role').eq('org_id', orgId).eq('user_id', userIdToRemove).single()
  ])

  if (!caller || caller.role !== 'admin') {
    return { error: 'Only admins can remove members.' }
  }
  if (!org) return { error: 'Org not found.' }
  if (!target) return { error: 'User is not a member of this org.' }

  const isCallerOwner = org.created_by === user.id
  const isTargetOwner = org.created_by === userIdToRemove

  if (isTargetOwner) {
    return { error: 'The Owner of the organization cannot be removed.' }
  }

  // Admins cannot remove other Admins (unless caller is the Owner)
  if (target.role === 'admin' && !isCallerOwner) {
    return { error: 'Only the Owner can remove another Admin.' }
  }

  // Cannot remove yourself via this button
  if (user.id === userIdToRemove) {
    return { error: 'You cannot kick out yourself using this action.' }
  }

  const { error: removeErr } = await supabaseAdmin
    .from('org_members')
    .delete()
    .eq('org_id', orgId)
    .eq('user_id', userIdToRemove)

  if (removeErr) {
    return { error: removeErr.message }
  }

  return { success: true }
}
