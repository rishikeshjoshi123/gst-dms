import { getMattersByClient } from '@/lib/actions/matter'
import { MATTER_STATUS_LABELS } from '@/lib/constants'
import { createClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from '@/lib/actions/org'
import { notFound } from 'next/navigation'
import Link from 'next/link'
import { Building2, FolderOpen, ChevronRight } from 'lucide-react'
import { NewMatterButton } from './NewMatterButton'
import { Badge } from '@/components/ui/badge'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'

export const metadata = { title: 'Client Details — GST Litigation DMS' }

export default async function ClientDetailPage(props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()

  if (!orgId) return null

  const { data: client } = await supabase
    .from('clients')
    .select('*')
    .eq('id', params.id)
    .eq('org_id', orgId)
    .single()

  if (!client) {
    notFound()
  }

  const matters = await getMattersByClient(params.id)

  const breadcrumbs = [
    { label: 'Clients', href: '/clients' },
    { label: client.name }
  ]

  return (
    <div className="flex flex-col gap-6 max-w-5xl animate-fade-in">
      <BreadcrumbSetter breadcrumbs={breadcrumbs} />

      {/* Client Header Card */}
      <div className="flex items-start gap-4 p-6 rounded-md bg-white border border-[var(--border-default)] shadow-[var(--shadow-sm)]">
        <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-md bg-blue-50 border border-blue-100">
          <Building2 size={24} className="text-[var(--accent)]" />
        </div>
        
        <div className="flex flex-col gap-1.5 min-w-0">
          <h1 className="text-[24px] font-semibold text-[var(--text-primary)]">{client.name}</h1>
          <div className="flex items-center gap-4 text-[14px] text-[var(--text-muted)] font-medium">
            {client.gstin && <span className="font-mono bg-slate-50 border border-slate-100 px-2 py-0.5 rounded text-[12px]">GSTIN: {client.gstin}</span>}
            {client.pan && <span className="font-mono bg-slate-50 border border-slate-100 px-2 py-0.5 rounded text-[12px]">PAN: {client.pan}</span>}
            {!client.gstin && !client.pan && <span>No identification numbers on file</span>}
          </div>
        </div>
      </div>

      {/* Matters Section */}
      <div className="flex flex-col gap-4 mt-2">
        <div className="flex items-center justify-between border-b border-[var(--border-default)] pb-3">
          <h2 className="text-[16px] font-semibold text-[var(--text-primary)]">Matters</h2>
          <NewMatterButton clientId={client.id} />
        </div>

        {matters.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center rounded-md border border-[var(--border-default)] bg-white shadow-[var(--shadow-sm)]">
            <FolderOpen size={32} className="text-[var(--text-muted)] mb-3" />
            <p className="text-[14px] text-[var(--text-primary)] font-semibold">No matters yet</p>
            <p className="text-[12px] text-[var(--text-muted)] mt-1 mb-5">Create a matter to start organizing documents for this client.</p>
            <NewMatterButton clientId={client.id} />
          </div>
        ) : (
          <div className="grid gap-3">
            {matters.map(matter => (
              <Link
                key={matter.id}
                href={`/matters/${matter.id}`}
                className="group flex items-center justify-between gap-4 p-4 rounded-md border border-[var(--border-default)] bg-white hover:shadow-[var(--shadow-sm)] hover:-translate-y-[1px] transition-all duration-[var(--duration-fast)]"
              >
                <div className="flex flex-col gap-1 min-w-0">
                  <div className="flex items-center gap-3">
                    <span className="font-medium text-[14px] text-[var(--text-primary)] group-hover:text-[var(--accent)] transition-colors">{matter.title}</span>
                    <Badge variant={matter.status === 'active' ? 'default' : 'muted'}>
                      {MATTER_STATUS_LABELS[matter.status]}
                    </Badge>
                  </div>
                  <div className="flex items-center gap-3 text-[12px] text-[var(--text-muted)] font-medium mt-1">
                    {matter.matter_code && (
                      <span className="font-mono bg-slate-50 border border-slate-100 px-1.5 py-0.5 rounded text-[11px] uppercase tracking-wider">{matter.matter_code}</span>
                    )}
                    <span>FY: {matter.financial_year}</span>
                  </div>
                </div>

                <ChevronRight size={16} className="text-[var(--text-muted)] group-hover:text-[var(--primary)] group-hover:translate-x-0.5 shrink-0 transition-all" />
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
