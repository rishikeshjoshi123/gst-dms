import { redirect } from 'next/navigation'
import { cookies } from 'next/headers'
import { createClient } from '@/lib/supabase/server'
import { SettingsClient } from './SettingsClient'
import type { Metadata } from 'next'

export const metadata: Metadata = { title: 'Settings' }

export default async function SettingsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const cookieStore = await cookies()
  const orgId = cookieStore.get('current_org_id')?.value
  if (!orgId) redirect('/onboarding')

  // Fetch org details
  const { data: org } = await supabase
    .from('organisations')
    .select('id, name, created_by')
    .eq('id', orgId)
    .single()

  if (!org) redirect('/onboarding')

  // Fetch members with user info via join on org_members
  const { data: memberRows } = await supabase
    .from('org_members')
    .select('user_id, role, joined_at')
    .eq('org_id', orgId)
    .order('joined_at', { ascending: true })

  // For each member, get their auth metadata via admin query isn't available client-side.
  // Instead, store display info from user_metadata at sign-up — check profiles via email.
  // We'll fetch email from auth.users via RPC or just use user_id to label members.
  // For now: show the current user's own info and label others by user_id (Phase 2 scope).
  const members = (memberRows ?? []).map((m) => ({
    user_id: m.user_id,
    role: m.role as 'admin' | 'associate' | 'viewer',
    email: m.user_id === user.id ? (user.email ?? '') : `User (${m.user_id.slice(0, 8)}…)`,
    full_name: m.user_id === user.id ? (user.user_metadata?.full_name ?? null) : null,
    joined_at: m.joined_at,
  }))

  const currentUserRole = members.find(m => m.user_id === user.id)?.role ?? 'member'

  // Pending invites
  const { data: pendingInvites } = await supabase
    .from('org_invites')
    .select('id, invited_email, role, status, expires_at')
    .eq('org_id', orgId)
    .in('status', ['pending', 'rejected'])
    .order('created_at', { ascending: false })

  return (
    <SettingsClient
      orgId={orgId}
      orgName={org.name}
      ownerId={org.created_by}
      currentUserId={user.id}
      currentUserRole={currentUserRole}
      members={members}
      pendingInvites={(pendingInvites ?? []).map(i => ({
        id: i.id,
        invited_email: i.invited_email,
        role: i.role as 'admin' | 'associate' | 'viewer',
        status: i.status,
        expires_at: i.expires_at,
      }))}
    />
  )
}
