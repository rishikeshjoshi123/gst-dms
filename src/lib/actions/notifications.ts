'use server'

import { createClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from '@/lib/actions/org'
import { revalidatePath } from 'next/cache'

export async function getNotifications() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { notifications: [], unreadCount: 0 }

  const { data } = await supabase
    .from('notifications')
    .select('*')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(50)

  const notifications = data ?? []
  const unreadCount = notifications.filter((n: any) => !n.is_read).length
  return { notifications, unreadCount }
}

export async function markNotificationRead(notificationId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Unauthorized' }

  const { error } = await supabase
    .from('notifications')
    .update({ is_read: true })
    .eq('id', notificationId)
    .eq('user_id', user.id)

  if (error) return { error: error.message }
  revalidatePath('/notifications')
  return { success: true }
}

export async function markAllNotificationsRead() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Unauthorized' }

  const { error } = await supabase
    .from('notifications')
    .update({ is_read: true })
    .eq('user_id', user.id)
    .eq('is_read', false)

  if (error) return { error: error.message }
  revalidatePath('/notifications')
  return { success: true }
}

export async function getUnreadNotificationCount(): Promise<number> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return 0

  const { count } = await supabase
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', user.id)
    .eq('is_read', false)

  return count ?? 0
}

export async function getRecentActivityLogs(limit = 15) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data } = await supabase
    .from('activity_logs')
    .select('*')
    .eq('org_id', orgId)
    .order('created_at', { ascending: false })
    .limit(limit)

  return data ?? []
}

export async function getUpcomingDeadlines(limit = 5) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const today = new Date().toISOString().split('T')[0]

  // First get matter IDs for this org
  const { data: matters } = await supabase
    .from('matters')
    .select('id')
    .eq('org_id', orgId)
    .is('deleted_at', null)

  if (!matters || matters.length === 0) return []
  const matterIds = matters.map((m: any) => m.id)

  const { data } = await supabase
    .from('deadlines')
    .select(`
      *,
      matters (
        id,
        title,
        matter_code,
        clients ( name )
      )
    `)
    .in('matter_id', matterIds)
    .eq('is_resolved', false)
    .gte('due_date', today)
    .order('due_date', { ascending: true })
    .limit(limit)

  return data ?? []
}

export async function getPendingReviewItems() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { needsReviewDocs: [], pendingLinks: [], openTasks: [], stagedDocs: [] }

  const [docsRes, linksRes, tasksRes, stagedRes] = await Promise.all([
    supabase
      .from('documents')
      .select(`
        id, doc_type, reference_number, review_reason, status, storage_path, created_at,
        matters ( id, title, matter_code, clients ( name ) )
      `)
      .eq('org_id', orgId)
      .eq('status', 'needs_review')
      .is('deleted_at', null)
      .order('created_at', { ascending: false }),

    supabase
      .from('document_links')
      .select(`
        id, link_type, confidence, status, created_at,
        from_doc:documents!document_links_from_doc_id_fkey ( id, doc_type, reference_number, matter_id ),
        to_doc:documents!document_links_to_doc_id_fkey ( id, doc_type, reference_number )
      `)
      .eq('status', 'pending')
      .order('confidence', { ascending: true })
      .limit(20),

    supabase
      .from('case_notes')
      .select(`
        id, content, action_item_due_date, created_at,
        matters ( id, title, matter_code )
      `)
      .eq('org_id', orgId)
      .eq('is_action_item', true)
      .eq('action_item_resolved', false)
      .is('deleted_at', null)
      .order('action_item_due_date', { ascending: true })
      .limit(20),

    supabase
      .from('staged_documents')
      .select('*')
      .eq('org_id', orgId)
      .eq('status', 'ready_to_assign')
      .order('created_at', { ascending: false })
      .limit(10),
  ])

  return {
    needsReviewDocs: docsRes.data ?? [],
    pendingLinks: linksRes.data ?? [],
    openTasks: tasksRes.data ?? [],
    stagedDocs: stagedRes.data ?? [],
  }
}
