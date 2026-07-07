import { getMatters } from '@/lib/actions/matter'
import { MATTER_STATUS_LABELS } from '@/lib/constants'
import Link from 'next/link'
import { FolderOpen, ChevronRight, Building2 } from 'lucide-react'
import { Badge } from '@/components/ui/badge'

export const metadata = { title: 'Matters — GST Litigation DMS' }

export default async function MattersPage() {
  const matters = await getMatters()

  return (
    <div className="flex flex-col gap-6 flex-1 overflow-y-auto pr-1 custom-scrollbar">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-page-title text-[var(--text-primary)]">Matters</h1>
          <p className="text-body text-[var(--text-muted)] mt-0.5">
            {matters.length} {matters.length === 1 ? 'matter' : 'matters'} across all clients
          </p>
        </div>
      </div>

      {/* Matter list */}
      {matters.length === 0 ? (
        <EmptyMatters />
      ) : (
        <div className="flex flex-col gap-3">
          {matters.map(matter => (
            <Link
              key={matter.id}
              href={`/matters/${matter.id}`}
              className="group flex flex-col p-[12px] rounded-[var(--radius-md)] bg-[var(--surface)] border border-[var(--border)] hover:shadow-[var(--shadow-sm)] hover:border-[var(--border-strong)] transition-all duration-[var(--duration-fast)]"
            >
              <div className="flex items-start justify-between">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-3">
                    <h3 className="text-section-heading text-[var(--text-primary)] truncate">{matter.title}</h3>
                    <Badge variant={matter.status === 'active' ? 'default' : 'muted'}>
                      {MATTER_STATUS_LABELS[matter.status]}
                    </Badge>
                  </div>
                  
                  <div className="flex items-center gap-3 mt-1 text-caption text-[var(--text-muted)]">
                    {matter.matter_code && (
                      <span className="font-mono bg-[var(--bg-base)] px-1.5 py-0.5 rounded border border-[var(--border)]">{matter.matter_code}</span>
                    )}
                    <span>FY {matter.financial_year}</span>
                    <span className="inline-flex items-center gap-1.5 border-l border-[var(--border-strong)] pl-3">
                      <Building2 size={12} />
                      {matter.clients?.name}
                    </span>
                  </div>
                </div>

                <div className="shrink-0 pl-4 flex items-center h-full pt-1">
                  <ChevronRight size={16} className="text-[var(--text-disabled)] group-hover:text-[var(--text-secondary)] group-hover:translate-x-[2px] transition-all" />
                </div>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}

function EmptyMatters() {
  return (
    <div className="flex flex-col items-center justify-center py-20 text-center rounded-md bg-white border border-dashed border-[--border-strong]">
      <div className="flex h-14 w-14 items-center justify-center rounded-full bg-[--bg-base] mb-4">
        <FolderOpen size={24} className="text-[--text-muted]" />
      </div>
      <h2 className="text-[16px] font-semibold text-[--text-primary]">No active matters</h2>
      <p className="text-[14px] text-[--text-muted] mt-1 max-w-sm mb-6 leading-relaxed">
        A matter represents a specific tax proceeding or advisory engagement. Head over to a client's profile to create one.
      </p>
      <Link
        href="/clients"
        className="inline-flex items-center justify-center whitespace-nowrap rounded-sm text-[14px] font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[--accent] disabled:pointer-events-none disabled:opacity-50 h-10 px-4 py-2 bg-[--accent] text-white hover:bg-[--accent-hover] shadow-[--shadow-sm]"
      >
        Go to Clients
      </Link>
    </div>
  )
}
