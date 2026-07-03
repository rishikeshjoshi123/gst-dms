'use server'

import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { sendOrgInviteEmail } from '@/lib/email'

// ── Helpers ──────────────────────────────────────────────────────

async function setCurrentOrg(orgId: string) {
  const cookieStore = await cookies()
  cookieStore.set('current_org_id', orgId, {
    httpOnly: false,
    path: '/',
    maxAge: 60 * 60 * 24 * 365,
    sameSite: 'lax',
  })
}

export async function getCurrentOrgId(): Promise<string | null> {
  const cookieStore = await cookies()
  return cookieStore.get('current_org_id')?.value ?? null
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

  // Create org
  const { data: org, error: orgErr } = await supabase
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

  // Check caller is admin
  const { data: caller } = await supabase
    .from('org_members')
    .select('role')
    .eq('org_id', orgId)
    .eq('user_id', user.id)
    .single()

  if (!caller || caller.role !== 'admin') {
    return { error: 'Only admins can invite members.' }
  }

  // Check existing invite
  const { data: existingInvite } = await supabase
    .from('org_invites')
    .select('id, status')
    .eq('org_id', orgId)
    .eq('invited_email', email)
    .eq('status', 'pending')
    .single()

  if (existingInvite) {
    return { error: 'A pending invite already exists for this email.' }
  }

  // Create invite (token is auto-generated in DB with DEFAULT)
  const { data: invite, error: inviteErr } = await supabase
    .from('org_invites')
    .insert({
      org_id: orgId,
      invited_email: email,
      invited_by: user.id,
      role: role as 'admin' | 'associate' | 'viewer',
    })
    .select('token')
    .single()

  if (inviteErr || !invite) {
    return { error: inviteErr?.message ?? 'Failed to create invite.' }
  }

  // Get org name for email
  const { data: org } = await supabase
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

// ── Accept Invite ─────────────────────────────────────────────────

export async function acceptInvite(token: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'You must be logged in to accept an invite.' }

  // Find valid invite
  const { data: invite, error: inviteErr } = await supabase
    .from('org_invites')
    .select('id, org_id, invited_email, role, expires_at, status')
    .eq('token', token)
    .single()

  if (inviteErr || !invite) return { error: 'Invalid or expired invite link.' }
  if (invite.status !== 'pending') return { error: `Invite is already ${invite.status}.` }
  if (new Date(invite.expires_at) < new Date()) return { error: 'This invite link has expired.' }
  if (invite.invited_email !== user.email) {
    return { error: `This invite was sent to ${invite.invited_email}. Please log in with that email.` }
  }

  // Add to org
  const { error: memberErr } = await supabase
    .from('org_members')
    .insert({ org_id: invite.org_id, user_id: user.id, role: invite.role })

  if (memberErr) {
    // Could be duplicate — check if already member
    if (memberErr.code === '23505') {
      return { error: 'You are already a member of this organisation.' }
    }
    return { error: memberErr.message }
  }

  // Update invite status
  await supabase
    .from('org_invites')
    .update({ status: 'accepted' })
    .eq('id', invite.id)

  await setCurrentOrg(invite.org_id)
  redirect('/dashboard')
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
