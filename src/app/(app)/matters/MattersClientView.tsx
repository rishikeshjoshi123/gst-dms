'use client'

import { useState, useMemo } from 'react'
import Link from 'next/link'
import { FolderOpen, ChevronRight, Building2, Search } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { MATTER_STATUS_LABELS, MatterStatus } from '@/lib/constants'

interface MattersClientViewProps {
  matters: any[]
}

export function MattersClientView({ matters }: MattersClientViewProps) {
  const [searchQuery, setSearchQuery] = useState('')

  const filteredMatters = useMemo(() => {
    if (!searchQuery.trim()) return matters
    const q = searchQuery.toLowerCase()
    return matters.filter(m => 
      m.title.toLowerCase().includes(q) || 
      (m.matter_code && m.matter_code.toLowerCase().includes(q)) ||
      (m.clients?.name && m.clients.name.toLowerCase().includes(q))
    )
  }, [matters, searchQuery])

  return (
    <div className="flex flex-col gap-6 flex-1 overflow-y-auto pr-1 custom-scrollbar">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 shrink-0">
        <div>
          <h1 className="text-page-title text-[var(--text-primary)]">Matters</h1>
          <p className="text-body text-[var(--text-muted)] mt-0.5">
            {matters.length} {matters.length === 1 ? 'matter' : 'matters'} across all clients
          </p>
        </div>
        
        <div className="flex items-center gap-3">
          <div className="relative">
            <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" />
            <input
              type="text"
              placeholder="Search matters..."
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              className="w-full md:w-64 h-9 pl-9 pr-3 rounded-lg text-sm bg-[var(--surface)] border border-[var(--border-strong)] text-[var(--text-primary)] placeholder:text-[var(--text-muted)] focus:outline-none focus:ring-2 focus:ring-[var(--primary)]/20 focus:border-[var(--primary)] transition-all"
            />
          </div>
        </div>
      </div>

      {/* Matter list */}
      {matters.length === 0 ? (
        <EmptyMatters />
      ) : filteredMatters.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-center rounded-xl bg-[var(--surface)] border border-[var(--border)]">
          <Search size={24} className="text-[var(--text-muted)] mb-3" />
          <p className="text-[var(--text-secondary)] text-sm">No matters match your search.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {filteredMatters.map(matter => (
            <Link
              key={matter.id}
              href={`/matters/${matter.id}`}
              className="group relative flex flex-col p-5 rounded-xl bg-[var(--surface)] border border-[var(--border)] hover:border-[var(--border-strong)] hover:shadow-[var(--shadow-md)] hover:-translate-y-0.5 transition-all duration-300 overflow-hidden"
            >
              <div className="absolute top-0 right-0 w-32 h-32 bg-gradient-to-bl from-indigo-500/5 to-transparent rounded-bl-full pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity" />
              
              <div className="flex items-start justify-between relative z-10">
                <div className="flex-1 min-w-0 pr-4">
                  <div className="flex items-center gap-3 mb-1">
                    <div className="w-8 h-8 rounded-lg bg-indigo-50 dark:bg-indigo-900/20 text-indigo-600 dark:text-indigo-400 flex items-center justify-center shrink-0">
                      <FolderOpen size={16} />
                    </div>
                    <h3 className="text-base font-bold text-[var(--text-primary)] truncate group-hover:text-[var(--primary)] transition-colors">
                      {matter.title}
                    </h3>
                  </div>
                  
                  <div className="flex items-center gap-2 mt-2">
                    <Badge variant={matter.status === 'active' ? 'default' : 'muted'} className="text-[10px] h-5 uppercase tracking-wider">
                      {MATTER_STATUS_LABELS[matter.status as MatterStatus]}
                    </Badge>
                    {matter.matter_code && (
                      <span className="font-mono text-[10px] bg-[var(--bg)] px-2 py-0.5 rounded border border-[var(--border)] text-[var(--text-secondary)]">
                        {matter.matter_code}
                      </span>
                    )}
                  </div>
                </div>

                <div className="shrink-0 flex items-center h-full pt-2">
                   <ChevronRight size={18} className="text-[var(--text-disabled)] group-hover:text-[var(--primary)] group-hover:translate-x-1 transition-all" />
                </div>
              </div>

              {/* Meta Footer */}
              <div className="mt-5 pt-4 border-t border-[var(--border)] flex items-center justify-between text-xs font-medium text-[var(--text-muted)] relative z-10">
                <div className="flex items-center gap-1.5 max-w-[50%] truncate">
                  <Building2 size={12} className="shrink-0" />
                  <span className="truncate">{matter.clients?.name || 'Unknown Client'}</span>
                </div>
                <div className="flex items-center gap-1.5 shrink-0">
                  <span className="text-[10px] uppercase tracking-wider text-[var(--text-disabled)]">FY</span>
                  {matter.financial_year || '—'}
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
    <div className="flex flex-col items-center justify-center py-20 text-center rounded-xl bg-[var(--surface)] border border-dashed border-[var(--border-strong)]">
      <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-indigo-500/10 to-violet-500/10 mb-5">
        <FolderOpen size={28} className="text-indigo-500" />
      </div>
      <h2 className="text-lg font-bold text-[var(--text-primary)]">No active matters</h2>
      <p className="text-sm text-[var(--text-muted)] mt-2 max-w-sm mb-6 leading-relaxed">
        A matter represents a specific tax proceeding or advisory engagement. Head over to a client's profile to create one.
      </p>
      <Link
        href="/clients"
        className="inline-flex items-center justify-center whitespace-nowrap rounded-lg text-sm font-semibold transition-all h-10 px-5 bg-[var(--accent)] text-white hover:opacity-90 shadow-[var(--shadow-sm)]"
      >
        Go to Clients
      </Link>
    </div>
  )
}
