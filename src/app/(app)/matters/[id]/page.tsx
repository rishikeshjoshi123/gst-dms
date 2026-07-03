import { getMatterById } from '@/lib/actions/matter'
import { MATTER_STATUS_LABELS } from '@/lib/constants'
import { getDocumentsByMatter } from '@/lib/actions/document'
import { notFound } from 'next/navigation'
import Link from 'next/link'
import { AlertTriangle, Plus } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { MatterTabs } from '@/components/matters/MatterTabs'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { Button } from '@/components/ui/button'

export const metadata = { title: 'Matter Workspace — GST Litigation DMS' }

export default async function MatterPage(props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  const matter = await getMatterById(params.id)
  
  if (!matter) {
    notFound()
  }

  const { proceedings, supporting, links } = await getDocumentsByMatter(params.id)
  const isClosed = matter.status === 'closed'

  const breadcrumbs = [
    { label: 'Clients', href: '/clients' },
    { label: matter.clients?.name || 'Unknown', href: `/clients/${matter.client_id}` },
    { label: matter.title }
  ]

  return (
    <div className="flex flex-col gap-6 max-w-5xl animate-fade-in">
      <BreadcrumbSetter breadcrumbs={breadcrumbs} />

      {/* Header Card */}
      <div className="flex flex-col gap-4 p-6 rounded-md bg-white border border-[var(--border-default)] shadow-[var(--shadow-sm)]">
        <div className="flex items-start justify-between">
          <div className="flex flex-col gap-3">
            <div className="flex items-center gap-3">
              <h1 className="text-[24px] font-semibold text-[var(--text-primary)]">{matter.title}</h1>
              <Badge variant={matter.status === 'active' ? 'default' : 'muted'}>
                {MATTER_STATUS_LABELS[matter.status]}
              </Badge>
            </div>
            <div className="flex items-center gap-4 text-[14px] text-[var(--text-muted)]">
              {matter.matter_code && (
                <span className="font-mono bg-slate-50 px-2 py-0.5 rounded text-[12px] border border-slate-100">{matter.matter_code}</span>
              )}
              <span className="font-medium">FY: {matter.financial_year}</span>
            </div>
            {matter.description && (
              <p className="text-[14px] text-[var(--text-secondary)] mt-1 max-w-2xl">{matter.description}</p>
            )}
          </div>
          
          {/* Add Documents Button */}
          {!isClosed && (
            <Link 
              href={`/inbox?matterId=${matter.id}`}
              className="inline-flex items-center justify-center whitespace-nowrap rounded-md text-sm font-medium h-9 px-4 py-2 bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-white shadow-sm transition-colors"
            >
              <Plus size={16} className="mr-2" />
              Add Documents
            </Link>
          )}
        </div>
      </div>

      {/* Warning Banner */}
      {isClosed && (
        <div className="flex items-center gap-3 p-4 rounded-md bg-red-50 border border-red-200 text-[var(--danger)] shadow-[var(--shadow-sm)]">
          <AlertTriangle size={18} />
          <p className="text-[14px] font-medium">This matter is marked as {MATTER_STATUS_LABELS[matter.status]}. Uploading new documents is disabled.</p>
        </div>
      )}

      <MatterTabs 
        proceedings={proceedings} 
        supporting={supporting} 
        links={links || []} 
      />
    </div>
  )
}
