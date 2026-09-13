'use server'

import { createClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from '@/lib/actions/org'
import { revalidatePath } from 'next/cache'
import { getSafeMemberDirectory } from '@/lib/organisation/member-directory'
import type { Json } from '@/lib/supabase/database.types'
import { getDateKeyInTimeZone, getDeadlineDayStatus, type DeadlineAttentionPayload } from '@/lib/deadlines/attention'

type ActivityMetadata = { [key: string]: Json | undefined }
type ActivityDocument = {
  id: string
  doc_type: string | null
  reference_number: string | null
  matters: { title: string } | { title: string }[] | null
}

function activityMetadata(value: Json | null): ActivityMetadata {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {}
}

function metadataText(metadata: ActivityMetadata, key: string): string | undefined {
  const value = metadata[key]
  return typeof value === 'string' ? value : undefined
}

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
  const unreadCount = notifications.filter((notification) => !notification.is_read).length
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
    // 1. Collect all link IDs where entity_type === 'document_link'
    const linkIds = new Set<string>()
    logs.forEach(log => {
      if (log.entity_type === 'document_link' && log.entity_id) {
        linkIds.add(log.entity_id)
      }
    })

    let linkMap = new Map<string, { from_doc_id: string; to_doc_id: string | null }>()
    if (linkIds.size > 0) {
      const { data: links } = await supabase
        .from('document_links')
        .select('id, from_doc_id, to_doc_id')
        .in('id', Array.from(linkIds))

      if (links) {
        linkMap = new Map(links.map(l => [l.id, { from_doc_id: l.from_doc_id, to_doc_id: l.to_doc_id }]))
      }
    }

    // 2. Collect all referenced document IDs across logs for dynamic resolution
    const docIds = new Set<string>()
    logs.forEach(log => {
      const meta = activityMetadata(log.metadata)
      const metadataFromDocumentId = metadataText(meta, 'from_doc_id')
      const metadataToDocumentId = metadataText(meta, 'to_doc_id')
      if (metadataFromDocumentId) docIds.add(metadataFromDocumentId)
      if (metadataToDocumentId) docIds.add(metadataToDocumentId)
      if (log.entity_type === 'document_link' && log.entity_id) {
        const link = linkMap.get(log.entity_id)
        if (link) {
          if (link.from_doc_id) docIds.add(link.from_doc_id)
          if (link.to_doc_id) docIds.add(link.to_doc_id)
        }
      }
      
      // Extract from legacy description: "Manually linked document <uuid> to <uuid>"
      if (log.description?.includes('Manually linked document')) {
        const match = log.description.match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}) to ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i)
        if (match) {
          docIds.add(match[1])
          docIds.add(match[2])
        }
      }

      if (log.entity_type === 'document' && log.entity_id) {
        docIds.add(log.entity_id)
      }
    })

    // Fetch live document details
    let docMap = new Map<string, ActivityDocument>()
    if (docIds.size > 0) {
      const { data: docs } = await supabase
        .from('documents')
        .select('id, doc_type, reference_number, matters(title)')
        .in('id', Array.from(docIds))

      if (docs) {
        docMap = new Map(docs.map((document) => [document.id, document]))
      }
    }

    // 3. Resolve only the caller-authorised tenant directory.
    const directory = await getSafeMemberDirectory()
    const userMap = new Map(directory.map((member) => [member.id, member.label]))

    return logs.map(log => {
      let description = log.description
      const meta = activityMetadata(log.metadata)
      let resolvedMeta: ActivityMetadata = { ...meta }

      let fromDocId = metadataText(meta, 'from_doc_id')
      let toDocId = metadataText(meta, 'to_doc_id')

      // Extract from legacy description if missing in metadata
      if (!fromDocId && !toDocId && description?.includes('Manually linked document')) {
        const match = description.match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}) to ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i)
        if (match) {
          fromDocId = match[1]
          toDocId = match[2]
        }
      }
      if (!fromDocId && log.entity_type === 'document_link' && log.entity_id) {
        const link = linkMap.get(log.entity_id)
        if (link) {
          fromDocId = link.from_doc_id
          toDocId = link.to_doc_id ?? undefined
        }
      }

      // Dynamically resolve document link descriptions & metadata from live DB records
      if (log.entity_type === 'document_link' && fromDocId && toDocId) {
        const fromDoc = docMap.get(fromDocId)
        const toDoc = docMap.get(toDocId)
        const fromType = fromDoc?.doc_type || fromDoc?.reference_number || metadataText(meta, 'from_doc_type') || 'Document'
        const toType = toDoc?.doc_type || toDoc?.reference_number || metadataText(meta, 'to_doc_type') || 'Document'
        
        let caseName = metadataText(meta, 'case_name')
        if (!caseName) {
           const fromMatter = fromDoc?.matters
           const toMatter = toDoc?.matters
           caseName = (Array.isArray(fromMatter) ? fromMatter[0]?.title : fromMatter?.title) || 
                      (Array.isArray(toMatter) ? toMatter[0]?.title : toMatter?.title) || 
                      'Case'
        }

        const isDelete = log.action.includes('deleted')
        description = isDelete
          ? `Deleted document link in ${caseName}`
          : `Manually linked ${fromType} and ${toType} in ${caseName}`

        resolvedMeta = {
          ...resolvedMeta,
          from_doc_type: fromType,
          from_ref: fromDoc?.reference_number,
          to_doc_type: toType,
          to_ref: toDoc?.reference_number,
          case_name: caseName
        }
      }

      // Clean up raw UUIDs in description from older logs if any
      if (description) {
        // Fix old "Manually linked document <uuid> to <uuid> as <type>"
        if (description.includes('Manually linked document') && description.match(/[0-9a-f]{8}-[0-9a-f]{4}/i)) {
          const match = description.match(/as (.+)$/i)
          const relType = match ? match[1] : 'related'
          description = `Manually linked documents as ${relType}`
        } else {
          // Fallback for other legacy logs with UUIDs
          description = description.replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, '(deleted)')
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

export async function getDeadlineAttention(limit = 5): Promise<DeadlineAttentionPayload> {
  const supabase = await createClient()
  const unavailable: DeadlineAttentionPayload = {
    status: 'unavailable',
    asOfDate: null,
    timeZone: null,
    items: [],
  }
  const { data: timezoneRows, error: timezoneError } = await supabase.rpc('get_current_organisation_operational_timezone')
  if (timezoneError || timezoneRows?.length !== 1) return unavailable

  const [{ org_id: orgId, timezone: timeZone }] = timezoneRows
  let asOfDate: string
  try {
    asOfDate = getDateKeyInTimeZone(new Date(), timeZone)
  } catch {
    return unavailable
  }
  const boundedLimit = Number.isInteger(limit) ? Math.min(Math.max(limit, 1), 20) : 5

  // First get matter IDs for this org
  const { data: matters, error: mattersError } = await supabase
    .from('matters')
    .select('id')
    .eq('org_id', orgId)
    .is('deleted_at', null)

  if (mattersError) return unavailable
  if (!matters || matters.length === 0) {
    return { status: 'available', asOfDate, timeZone, items: [] }
  }
  const matterIds = matters.map((matter) => matter.id)

  const { data, error } = await supabase
    .from('deadlines')
    .select(`
      id,
      due_date,
      type,
      description,
      matters (
        title,
        clients ( name )
      )
    `)
    .in('matter_id', matterIds)
    .eq('is_resolved', false)
    .order('due_date', { ascending: true })
    .limit(boundedLimit)

  if (error) return unavailable
  try {
    return {
      status: 'available',
      asOfDate,
      timeZone,
      items: (data ?? []).map((deadline) => {
        getDeadlineDayStatus(deadline.due_date, asOfDate)
        return {
          id: deadline.id,
          dueDate: deadline.due_date,
          type: deadline.type,
          description: deadline.description,
          matter: {
            title: deadline.matters.title,
            clientName: deadline.matters.clients.name,
          },
        }
      }),
    }
  } catch {
    return unavailable
  }
}
