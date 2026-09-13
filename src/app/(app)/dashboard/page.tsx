import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { readReviewQueue } from '@/lib/review/reader'
import { getDeadlineAttention, getRecentActivityLogs } from '@/lib/actions/notifications'
import { DashboardContent } from './DashboardContent'
import type { Metadata } from 'next'
import { getCurrentOrgId } from '@/lib/actions/org'

export const metadata: Metadata = { title: 'Dashboard' }

async function getDashboardStats(orgId: string) {
  const supabase = await createClient()
  const [clients, matters, documents] = await Promise.all([
    supabase.from('clients').select('id', { count: 'exact', head: true }).eq('org_id', orgId).eq('record_state', 'active').is('deleted_at', null),
    supabase.from('matters').select('id', { count: 'exact', head: true }).eq('org_id', orgId).eq('record_state', 'active').is('deleted_at', null),
    supabase.from('documents').select('id', { count: 'exact', head: true }).eq('org_id', orgId).eq('record_state', 'active').is('deleted_at', null),
  ])
  return {
    clients: clients.count ?? 0,
    matters: matters.count ?? 0,
    documents: documents.count ?? 0,
  }
}

export default async function DashboardPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const orgId = await getCurrentOrgId()
  if (!orgId) redirect('/onboarding')

  const [stats, { data: org }, reviewQueue, activityLogs, deadlineAttention] = await Promise.all([
    getDashboardStats(orgId),
    supabase.from('organisations').select('name').eq('id', orgId).single(),
    readReviewQueue(undefined, 5),
    getRecentActivityLogs(15),
    getDeadlineAttention(5),
  ])

  const firstName = user.user_metadata?.full_name?.split(' ')[0] ?? 'there'
  const hour = new Date().getHours()
  const greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening'

  const statCards = [
    { label: 'Active Clients',  value: stats.clients,           href: '/clients' },
    { label: 'Open Matters',    value: stats.matters,           href: '/matters' },
    { label: 'Documents',       value: stats.documents,         href: '/clients' },
    { label: 'Pending Review',  value: reviewQueue.totalCount,  href: '/review'  },
  ]

  return (
    <DashboardContent
      firstName={firstName}
      greeting={greeting}
      orgName={org?.name ?? ''}
      stats={stats}
      needsReviewDocs={reviewQueue.items}
      statCards={statCards}
      activityLogs={activityLogs}
      deadlineAttention={deadlineAttention}
    />
  )
}
