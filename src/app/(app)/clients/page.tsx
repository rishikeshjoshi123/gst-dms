import { getClients } from '@/lib/actions/client'
import { NewClientButton } from './NewClientButton'
import Link from 'next/link'
import { Building2, ArrowRight, ChevronRight } from 'lucide-react'

export const metadata = { title: 'Clients — GST Litigation DMS' }

export default async function ClientsPage() {
  const clients = await getClients()

  return (
    <div className="flex flex-col gap-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-page-title text-[var(--text-primary)]">Clients</h1>
          <p className="text-body text-[var(--text-muted)] mt-0.5">
            {clients.length} {clients.length === 1 ? 'client' : 'clients'} in this workspace
          </p>
        </div>
        <NewClientButton />
      </div>

      {/* Client list */}
      {clients.length === 0 ? (
        <EmptyClients />
      ) : (
        <div className="flex flex-col gap-3">
          {clients.map(client => (
            <Link
              key={client.id}
              href={`/clients/${client.id}`}
              className="group flex flex-col p-[12px] rounded-[var(--radius-md)] bg-[var(--surface)] border border-[var(--border)] hover:shadow-[var(--shadow-sm)] hover:border-[var(--border-strong)] transition-all duration-[var(--duration-fast)]"
            >
              <div className="flex items-start justify-between">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-3">
                    <h3 className="text-section-heading text-[var(--text-primary)] truncate">{client.name}</h3>
                    {client.totalMatters > 0 && (
                       <span className="text-caption text-[var(--text-secondary)] uppercase">
                         {client.totalMatters} {client.totalMatters === 1 ? 'Matter' : 'Matters'} ({client.openMatters} Open)
                       </span>
                    )}
                  </div>
                  
                  <div className="flex items-center gap-3 mt-1 text-caption text-[var(--text-muted)]">
                    {client.gstin && (
                      <span className="font-mono">{client.gstin}</span>
                    )}
                    {client.pan && (
                      <span>PAN: {client.pan}</span>
                    )}
                    {!client.gstin && !client.pan && (
                      <span className="text-[var(--text-disabled)]">No GSTIN on file</span>
                    )}
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

function EmptyClients() {
  return (
    <div className="flex flex-col items-center justify-center py-20 text-center rounded-md bg-white border border-dashed border-[--border-strong]">
      <div className="flex h-14 w-14 items-center justify-center rounded-full bg-[--bg-base] mb-4">
        <Building2 size={24} className="text-[--text-muted]" />
      </div>
      <h2 className="text-[16px] font-semibold text-[--text-primary]">Your client list is empty</h2>
      <p className="text-[14px] text-[--text-muted] mt-1 max-w-sm leading-relaxed">
        Add a client to start organizing their tax matters and proceedings in one secure place.
      </p>
      <div className="mt-6">
        <NewClientButton />
      </div>
    </div>
  )
}
