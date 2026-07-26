import { getMatterById } from '@/lib/actions/matter'
import { MATTER_STATUS_LABELS } from '@/lib/constants'
import { getDocumentsByMatter } from '@/lib/actions/document'
import { getWikiSections } from '@/lib/actions/wiki'
import { getNotes } from '@/lib/actions/notes'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from '@/lib/actions/org'
import { notFound } from 'next/navigation'
import Link from 'next/link'
import { AlertTriangle, Plus } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { MatterTabs } from '@/components/matters/MatterTabs'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { Button } from '@/components/ui/button'

export const metadata = { title: 'Matter Workspace — GST Litigation DMS' }

export default async function MatterPage(props: { 
  params: Promise<{ id: string }>
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const params = await props.params;
  const searchParams = await props.searchParams;
  const fromReview = searchParams?.from === 'review'
  const matter = await getMatterById(params.id)

  if (!matter) {
    notFound()
  }

  const supabase = await createClient()

  const { proceedings, supporting, links } = await getDocumentsByMatter(params.id)
  const wikiSections = await getWikiSections(params.id)
  const notes = await getNotes({ matterId: params.id })

  const orgId = await getCurrentOrgId()
  const { data: memberRows } = await supabase
    .from('org_members')
    .select('user_id, role')
    .eq('org_id', orgId || '')

  const serviceClient = createServiceClient()
  const { data: { users: authUsers } } = await serviceClient.auth.admin.listUsers()
  const userMap = new Map(authUsers.map(u => [u.id, u.email]))

  const usersList = (memberRows ?? []).map((m: any) => ({
    id: m.user_id,
    email: userMap.get(m.user_id) || `User (${m.user_id.slice(0, 8)})`
  }))

  const isClosed = matter.status === 'closed'

  const breadcrumbs = fromReview
    ? [
        { label: 'Pending Review', href: '/review' },
        { label: matter.clients?.name || 'Unknown', href: `/clients/${matter.client_id}` },
        { label: matter.title }
      ]
    : [
        { label: 'Clients', href: '/clients' },
        { label: matter.clients?.name || 'Unknown', href: `/clients/${matter.client_id}` },
        { label: matter.title }
      ]

  return (
    <div className="flex flex-col flex-1 overflow-hidden h-full animate-fade-in -mt-2 ">
      <BreadcrumbSetter breadcrumbs={breadcrumbs} />

      {/* Warning Banner */}
      {isClosed && (
        <div className="flex items-center gap-3 p-3 mb-4 rounded-md bg-red-50 border border-red-200 text-[var(--danger)] shadow-[var(--shadow-sm)] shrink-0">
          <AlertTriangle size={18} />
          <p className="text-[14px] font-medium">This matter is marked as {MATTER_STATUS_LABELS[matter.status]}. Uploading new documents is disabled.</p>
        </div>
      )}

      <MatterTabs
        matter={matter}
        proceedings={proceedings}
        supporting={supporting}
        links={links || []}
        wikiSections={wikiSections || []}
        notes={notes || []}
        users={usersList}
      />
    </div>
  )
}
