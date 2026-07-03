import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getNeedsReviewDocuments } from '@/lib/actions/document'
import { DashboardContent } from './DashboardContent'
import type { Metadata } from 'next'

export const metadata: Metadata = { title: 'Dashboard' }

async function getDashboardStats(orgId: string) {
  const supabase = await createClient()

  const [clients, matters, documents] = await Promise.all([
    supabase.from('clients').select('id', { count: 'exact', head: true }).eq('org_id', orgId),
    supabase.from('matters').select('id', { count: 'exact', head: true }).eq('org_id', orgId),
    supabase.from('documents').select('id', { count: 'exact', head: true }).eq('org_id', orgId),
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

  const cookieStore = await cookies()
  const orgId = cookieStore.get('current_org_id')?.value
  if (!orgId) redirect('/onboarding')

  const [stats, { data: org }, needsReviewDocs] = await Promise.all([
    getDashboardStats(orgId),
    supabase.from('organisations').select('name').eq('id', orgId).single(),
    getNeedsReviewDocuments(),
  ])

  const firstName = user.user_metadata?.full_name?.split(' ')[0] ?? 'there'
  const hour = new Date().getHours()
  const greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening'

  const statCards = [
    {
      label: 'Active Clients',
      value: stats.clients,
      href: '/clients',
    },
    {
      label: 'Open Matters',
      value: stats.matters,
      href: '/matters',
    },
    {
      label: 'Documents',
      value: stats.documents,
      href: '/clients',
    },
    {
      label: 'Pending Review',
      value: needsReviewDocs.length,
      href: '/dashboard',
    },
  ]

  return (
    <DashboardContent
      firstName={firstName}
      greeting={greeting}
      orgName={org?.name ?? ''}
      stats={stats}
      needsReviewDocs={needsReviewDocs}
      statCards={statCards}
    />
  )
}
