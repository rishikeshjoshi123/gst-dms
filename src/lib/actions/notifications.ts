'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
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

export async function getRecentActivityLogs(limit = 50) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data: logs } = await supabase
    .from('activity_logs')
    .select('*')
    .eq('org_id', orgId)
    .order('created_at', { ascending: false })
    .limit(limit)

  if (!logs || logs.length === 0) return []

  try {
    const db = createServiceClient()
    
    // 1. Collect all referenced document IDs across logs for dynamic resolution
    const docIds = new Set<string>()
    logs.forEach(log => {
      const meta = log.metadata as Record<string, any> | null
      if (meta) {
        if (meta.from_doc_id) docIds.add(meta.from_doc_id)
        if (meta.to_doc_id) docIds.add(meta.to_doc_id)
      }
      if (log.entity_type === 'document' && log.entity_id) {
        docIds.add(log.entity_id)
      }
    })

    // Fetch live document details
    let docMap = new Map<string, any>()
    if (docIds.size > 0) {
      const { data: docs } = await db
        .from('documents')
        .select('id, doc_type, reference_number, matters(title)')
        .in('id', Array.from(docIds))

      if (docs) {
        docMap = new Map(docs.map(d => [d.id, d]))
      }
    }

    // 2. Fetch auth users
    const { data: { users: authUsers } } = await db.auth.admin.listUsers()
    const userMap = new Map((authUsers || []).map(u => [
      u.id,
      u.user_metadata?.full_name || u.email || `User (${u.id.slice(0, 8)})`
    ]))

    return logs.map(log => {
      let description = log.description
      const meta = (log.metadata as Record<string, any>) || {}
      let resolvedMeta: Record<string, any> = { ...meta }

      // Dynamically resolve document link descriptions & metadata from live DB records
      if (log.entity_type === 'document_link' && meta.from_doc_id && meta.to_doc_id) {
        const fromDoc = docMap.get(meta.from_doc_id)
        const toDoc = docMap.get(meta.to_doc_id)
        const fromType = fromDoc?.doc_type || fromDoc?.reference_number || meta.from_doc_type || 'Document'
        const toType = toDoc?.doc_type || toDoc?.reference_number || meta.to_doc_type || 'Document'
        const caseName = (fromDoc?.matters as any)?.title || (toDoc?.matters as any)?.title || meta.case_name || 'Matter'

        const isDelete = log.action.includes('deleted')
        description = isDelete
          ? `Deleted link between ${fromType} and ${toType} of ${caseName}`
          : `Manually linked ${fromType} and ${toType} of ${caseName}`

        resolvedMeta = {
          ...resolvedMeta,
          from_doc_type: fromType,
          from_ref: fromDoc?.reference_number,
          to_doc_type: toType,
          to_ref: toDoc?.reference_number,
          case_name: caseName
        }
      }

      return {
        ...log,
        description,
        metadata: resolvedMeta,
        user_email: (log.user_id ? userMap.get(log.user_id) : null) || 'System'
      }
    })
  } catch (err) {
    console.error('Failed to resolve activity log details:', err)
  }

  return logs
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
