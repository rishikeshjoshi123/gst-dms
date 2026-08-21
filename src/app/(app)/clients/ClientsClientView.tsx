'use client'

import { useState, useMemo } from 'react'
import Link from 'next/link'
import { Building2, ChevronRight, Search, Activity, FileText, FolderOpen } from 'lucide-react'
import { NewClientButton } from './NewClientButton'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'

interface ClientsClientViewProps {
  clients: any[]
}

export function ClientsClientView({ clients }: ClientsClientViewProps) {
  const [searchQuery, setSearchQuery] = useState('')

  const filteredClients = useMemo(() => {
    if (!searchQuery.trim()) return clients
    const q = searchQuery.toLowerCase()
    return clients.filter(c => 
      c.name.toLowerCase().includes(q) || 
      (c.gstin && c.gstin.toLowerCase().includes(q)) ||
      (c.pan && c.pan.toLowerCase().includes(q))
    )
  }, [clients, searchQuery])

  return (
    <div className="flex flex-col gap-6 flex-1 overflow-y-auto pr-1 custom-scrollbar">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Clients' }]} />
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 shrink-0">
        <div>
          <h1 className="text-page-title text-[var(--text-primary)]">Clients</h1>
          <p className="text-body text-[var(--text-muted)] mt-0.5">
            {clients.length} {clients.length === 1 ? 'client' : 'clients'} in this workspace
          </p>
        </div>
        
        <div className="flex items-center gap-3">
          <div className="relative">
            <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" />
            <input
              type="text"
              placeholder="Search clients..."
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              className="w-full md:w-64 h-9 pl-9 pr-3 rounded-lg text-sm bg-[var(--surface)] border border-[var(--border-strong)] text-[var(--text-primary)] placeholder:text-[var(--text-muted)] focus:outline-none focus:ring-2 focus:ring-[var(--primary)]/20 focus:border-[var(--primary)] transition-all"
            />
          </div>
          <NewClientButton />
        </div>
      </div>

      {/* Client list */}
      {clients.length === 0 ? (
        <EmptyClients />
      ) : filteredClients.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-center rounded-[var(--radius-md)] bg-[var(--surface)] border border-[var(--border)]">
          <Search size={24} className="text-[var(--text-muted)] mb-3" />
          <p className="text-[var(--text-secondary)] text-sm">No clients match your search.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {filteredClients.map(client => (
            <Link
              key={client.id}
              href={`/clients/${client.id}`}
              className="group relative flex flex-col p-5 rounded-[var(--radius-md)] bg-[var(--surface)] border border-[var(--border)] hover:border-[var(--border-strong)] transition-colors duration-150 overflow-hidden"
            >
              <div className="flex items-start justify-between relative z-10">
                <div className="flex-1 min-w-0 pr-4">
                  <div className="flex items-center gap-3 mb-1">
                    <div className="w-8 h-8 rounded-lg bg-[var(--accent-muted)] text-[var(--primary)] flex items-center justify-center shrink-0">
                      <Building2 size={16} />
                    </div>
                    <h3 className="text-base font-bold text-[var(--text-primary)] truncate group-hover:text-[var(--primary)] transition-colors">
                      {client.name}
                    </h3>
                  </div>
                  
                  <div className="flex flex-wrap items-center gap-x-4 gap-y-2 mt-3 text-[11px] font-medium text-[var(--text-muted)]">
                    {client.gstin ? (
                      <span className="flex items-center gap-1.5 px-2 py-0.5 rounded-md bg-[var(--bg)] border border-[var(--border)]">
                        <span className="text-[9px] uppercase tracking-wider text-[var(--text-disabled)]">GSTIN</span>
                        <span className="font-mono text-[var(--text-secondary)]">{client.gstin}</span>
                      </span>
                    ) : (
                      <span className="flex items-center gap-1.5 px-2 py-0.5 rounded-md bg-[var(--bg)] border border-dashed border-[var(--border)] text-[var(--text-disabled)]">
                        No GSTIN
                      </span>
                    )}
                    
                    {client.pan && (
                      <span className="flex items-center gap-1.5 px-2 py-0.5 rounded-md bg-[var(--bg)] border border-[var(--border)]">
                        <span className="text-[9px] uppercase tracking-wider text-[var(--text-disabled)]">PAN</span>
                        <span className="font-mono text-[var(--text-secondary)]">{client.pan}</span>
                      </span>
                    )}
                  </div>
                </div>

                <div className="shrink-0 pl-4 flex items-center gap-2">
                   <ChevronRight size={18} className="text-[var(--text-disabled)] group-hover:text-[var(--primary)] group-hover:translate-x-1 transition-all" />
                </div>
              </div>

              {/* Stats Footer */}
              <div className="mt-5 pt-4 border-t border-[var(--border)] grid grid-cols-3 gap-4 relative z-10">
                <div className="flex flex-col gap-1">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] flex items-center gap-1">
                    <FolderOpen size={10} /> Matters
                  </span>
                  <span className="text-sm font-semibold text-[var(--text-primary)]">{client.totalMatters || 0}</span>
                </div>
                <div className="flex flex-col gap-1">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] flex items-center gap-1">
                    <Activity size={10} /> Open
                  </span>
                  <span className="text-sm font-semibold text-[var(--primary)]">{client.openMatters || 0}</span>
                </div>
                <div className="flex flex-col gap-1">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] flex items-center gap-1">
                    <FileText size={10} /> Documents
                  </span>
                  <span className="text-sm font-semibold text-[var(--text-primary)]">—</span>
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
    <div className="flex flex-col items-center justify-center py-20 text-center rounded-[var(--radius-md)] bg-[var(--surface)] border border-dashed border-[var(--border-strong)]">
      <div className="flex h-16 w-16 items-center justify-center rounded-[var(--radius-lg)] bg-[var(--accent-muted)] mb-5">
        <Building2 size={28} className="text-[var(--primary)]" />
      </div>
      <h2 className="text-lg font-bold text-[var(--text-primary)]">Your client list is empty</h2>
      <p className="text-sm text-[var(--text-muted)] mt-2 max-w-sm leading-relaxed">
        Add a client to start organizing their tax matters and proceedings in one secure place.
      </p>
      <div className="mt-6">
        <NewClientButton />
      </div>
    </div>
  )
}
