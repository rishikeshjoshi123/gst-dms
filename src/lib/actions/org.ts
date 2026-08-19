'use server'

import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { sendOrgInviteEmail } from '@/lib/email'

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

  // The cookie is only a UI preference, not an authorization grant. Every
  // server action that uses this helper may subsequently use a service-role
  // client, so validate both the authenticated user and their membership here.
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return null

  if (orgId) {
    const { data: membership } = await supabase
      .from('org_members')
      .select('org_id')
      .eq('user_id', user.id)
      .eq('org_id', orgId)
      .maybeSingle()
    if (membership) return membership.org_id
  }

  // A preference can be absent or stale (for example, an older session). Use
  // a verified membership for this request; a later sign-in/org switch writes
  // the preference from a Server Action.
  const { data: fallbackMembership } = await supabase
    .from('org_members')
    .select('org_id')
    .eq('user_id', user.id)
    .order('joined_at', { ascending: true })
    .limit(1)
    .maybeSingle()

  return fallbackMembership?.org_id ?? null
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

  const { createServiceClient } = await import('@/lib/supabase/server')
  const supabaseAdmin = createServiceClient()

  // Check if user is already in an org
  const { data: existingMember } = await supabaseAdmin
    .from('org_members')
    .select('org_id')
    .eq('user_id', user.id)
    .maybeSingle()

  if (existingMember) {
    return { error: 'You are already a member of an organization. You must leave it before creating a new one.' }
  }

  const { data: org, error: orgErr } = await supabaseAdmin
    .from('organisations')
    .insert({ name, created_by: user.id })
    .select('id')
    .single()

  if (orgErr || !org) {
    console.error('Organisation Creation Error:', orgErr)
    return { error: orgErr?.message ?? 'Failed to create organisation.' }
  }

  await setCurrentOrg(org.id)
  redirect('/dashboard')
}

// ── Switch Organisation ───────────────────────────────────────────

export async function switchOrganisation(orgId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  // Verify membership
  const { data: member } = await supabase
    .from('org_members')
    .select('id')
    .eq('org_id', orgId)
    .eq('user_id', user.id)
    .single()

  if (!member) return { error: 'Access denied.' }

  await setCurrentOrg(orgId)
  redirect('/dashboard')
}

// ── Invite Member ─────────────────────────────────────────────────

export async function inviteMember(formData: FormData) {
  const supabase = await createClient()
  const email = (formData.get('email') as string)?.trim().toLowerCase()
  const role = (formData.get('role') as string) ?? 'member'
  const orgId = await getCurrentOrgId()

  if (!email) return { error: 'Email is required.' }
  if (!orgId) return { error: 'No active organisation.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { createServiceClient } = await import('@/lib/supabase/server')
  const supabaseAdmin = createServiceClient()

  // Check caller is admin
  const { data: caller } = await supabaseAdmin
    .from('org_members')
    .select('role')
    .eq('org_id', orgId)
    .eq('user_id', user.id)
    .single()

  if (!caller || caller.role !== 'admin') {
    return { error: 'Only admins can invite members.' }
  }

  // 1. Check if the invited email is already in ANY organization
  const { data: isAlreadyInOrg } = await supabaseAdmin.rpc('is_email_in_any_org', { search_email: email })
  if (isAlreadyInOrg) {
    return { error: 'This user is already a member of an organization and cannot be invited.' }
  }

  // 2. Check for an existing pending invite
  const { data: existingInvite } = await supabaseAdmin
    .from('org_invites')
    .select('id, status')
    .eq('org_id', orgId)
    .eq('invited_email', email)
    .eq('status', 'pending')
    .maybeSingle()

  if (existingInvite) {
    return { error: 'A pending invite already exists for this email.' }
  }

  // Create invite
  const { data: invite, error: inviteErr } = await supabaseAdmin
    .from('org_invites')
    .insert({
      org_id: orgId,
      invited_email: email,
      invited_by: user.id,
      role: role as 'admin' | 'associate' | 'viewer',
    })
    .select('id, token')
    .single()

  if (inviteErr || !invite) {
    return { error: inviteErr?.message ?? 'Failed to create invite.' }
  }

  // Get org name for email
  const { data: org } = await supabaseAdmin
    .from('organisations')
    .select('name')
    .eq('id', orgId)
    .single()

  // Send invite email (no-op in dev)
  await sendOrgInviteEmail({
    to: email,
    orgName: org?.name ?? 'your organisation',
    inviterName: user.user_metadata?.full_name ?? user.email ?? 'A team member',
    inviteToken: invite.token,
    appUrl: process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000',
  })

  return { success: true }
}

// ── Get Pending Invites For User (Onboarding) ─────────────────────

export async function getMyPendingInvites() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user || !user.email) return []

  const { createServiceClient } = await import('@/lib/supabase/server')
  const supabaseAdmin = createServiceClient()

  const { data, error } = await supabaseAdmin
    .from('org_invites')
    .select('id, role, expires_at, organisations(id, name)')
    .ilike('invited_email', user.email.trim())
    .eq('status', 'pending')

  if (error) {
    console.error('Error fetching pending invites:', error)
    return []
  }

  return (data ?? []).filter(inv => new Date(inv.expires_at) > new Date()).map(inv => ({
    id: inv.id,
    role: inv.role,
    orgName: (inv.organisations as { id: string; name: string })?.name ?? 'Organisation',
  }))
}

// ── Accept / Reject Invite (Tokenless) ────────────────────────────

export async function acceptInvite(inviteId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user || !user.email) return { error: 'You must be logged in to accept an invite.' }

  const { createServiceClient } = await import('@/lib/supabase/server')
  const supabaseAdmin = createServiceClient()

  // Check if user is already in an org
  const { data: existingMember } = await supabaseAdmin
    .from('org_members')
    .select('org_id')
    .eq('user_id', user.id)
    .maybeSingle()

  if (existingMember) {
    return { error: 'You are already a member of an organization. You must leave it before joining a new one.' }
  }

  // Find valid invite
  const { data: invite, error: inviteErr } = await supabaseAdmin
    .from('org_invites')
    .select('id, org_id, invited_email, role, expires_at, status')
    .eq('id', inviteId)
    .single()

  if (inviteErr || !invite) return { error: 'Invalid invite.' }
  if (invite.status !== 'pending') return { error: `Invite is already ${invite.status}.` }
  if (new Date(invite.expires_at) < new Date()) return { error: 'This invite has expired.' }
  if (invite.invited_email.toLowerCase() !== user.email.toLowerCase()) {
    return { error: `This invite was sent to ${invite.invited_email}.` }
  }

  // Add to org
  const { error: memberErr } = await supabaseAdmin
    .from('org_members')
    .insert({ org_id: invite.org_id, user_id: user.id, role: invite.role })

  if (memberErr) {
    if (memberErr.code === '23505') {
      return { error: 'You are already a member of an organization.' }
    }
    return { error: memberErr.message }
  }

  // Update invite status
  await supabaseAdmin
    .from('org_invites')
    .update({ status: 'accepted' })
    .eq('id', invite.id)

  await setCurrentOrg(invite.org_id)
  redirect('/dashboard')
}

export async function rejectInvite(inviteId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user || !user.email) return { error: 'Not logged in.' }

  const { createServiceClient } = await import('@/lib/supabase/server')
  const supabaseAdmin = createServiceClient()

  const { data: invite, error: inviteErr } = await supabaseAdmin
    .from('org_invites')
    .select('id, invited_email, status')
    .eq('id', inviteId)
    .single()

  if (inviteErr || !invite) return { error: 'Invalid invite.' }
  if (invite.invited_email.toLowerCase() !== user.email.toLowerCase()) return { error: 'Access denied.' }
  if (invite.status !== 'pending') return { error: `Invite is already ${invite.status}.` }

  await supabaseAdmin
    .from('org_invites')
    .update({ status: 'rejected' })
    .eq('id', invite.id)

  return { success: true }
}

// ── Get user's organisations ──────────────────────────────────────

export async function getUserOrgs() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return []

  const { data } = await supabase
    .from('org_members')
    .select('role, organisations(id, name, created_at)')
    .eq('user_id', user.id)

  return (data ?? []).map((m) => ({
    ...(m.organisations as { id: string; name: string; created_at: string }),
    role: m.role,
  }))
}

// ── Admin: Get Pending Invites for Settings ───────────────────────

export async function getPendingInvitesForOrg() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return []

  const { data: membership } = await supabase
    .from('org_members')
    .select('role')
    .eq('org_id', orgId)
    .eq('user_id', user.id)
    .maybeSingle()
  if (membership?.role !== 'admin') return []

  const { createServiceClient } = await import('@/lib/supabase/server')
  const supabaseAdmin = createServiceClient()

  const { data } = await supabaseAdmin
    .from('org_invites')
    .select('id, invited_email, role, status, created_at')
    .eq('org_id', orgId)
    .in('status', ['pending', 'rejected'])
    .order('created_at', { ascending: false })

  return data ?? []
}

export async function deleteInvite(inviteId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active org.' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const { createServiceClient } = await import('@/lib/supabase/server')
  const supabaseAdmin = createServiceClient()

  const { data: caller } = await supabaseAdmin
    .from('org_members')
    .select('role')
    .eq('org_id', orgId)
    .eq('user_id', user.id)
    .single()

  if (!caller || caller.role !== 'admin') return { error: 'Only admins can delete invites.' }

  await supabaseAdmin
    .from('org_invites')
    .delete()
    .eq('id', inviteId)
    .eq('org_id', orgId)

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
