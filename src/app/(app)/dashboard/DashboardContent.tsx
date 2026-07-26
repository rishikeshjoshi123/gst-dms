'use client'

import { useState, useEffect, useTransition, useMemo } from 'react'
import { searchAll, SearchResultItem } from '@/lib/actions/search'
import { NeedsAttentionPanel } from './NeedsAttentionPanel'
import {
  ArrowUpRight, FileText, Search, Users, FolderOpen,
  Loader2, X, Activity, Calendar, Clock, ChevronRight, ChevronDown, ChevronLeft,
  AlertCircle, Zap, Link2, FileCheck, ShieldAlert, Code, Filter, Info, User
} from 'lucide-react'
import { cn } from '@/lib/utils'
import Link from 'next/link'
import { formatDistanceToNow, differenceInDays } from 'date-fns'
import { useBreadcrumbs } from '@/components/nav/BreadcrumbContext'

interface DashboardContentProps {
  firstName: string
  greeting: string
  orgName: string
  stats: { clients: number; matters: number; documents: number }
  needsReviewDocs: any[]
  statCards: Array<{ label: string; value: number; href: string }>
  activityLogs: any[]
  upcomingDeadlines: any[]
}

const LOGS_PER_PAGE = 8

const ENTITY_META: Record<string, { icon: React.FC<any>; color: string; gradient: string }> = {
  document:          { icon: FileText,   color: 'text-blue-500',   gradient: 'from-blue-500 to-indigo-500' },
  matter:            { icon: FolderOpen, color: 'text-indigo-500', gradient: 'from-indigo-500 to-violet-500' },
  client:            { icon: Users,      color: 'text-emerald-500',gradient: 'from-emerald-500 to-teal-500' },
  case_note:         { icon: FileCheck,  color: 'text-violet-500', gradient: 'from-violet-500 to-purple-500' },
  document_link:     { icon: Link2,      color: 'text-amber-500',  gradient: 'from-amber-500 to-orange-500' },
  deadline:          { icon: Calendar,   color: 'text-rose-500',   gradient: 'from-rose-500 to-pink-500' },
  staged_document:   { icon: Zap,        color: 'text-cyan-500',   gradient: 'from-cyan-500 to-blue-500' },
  organisation:      { icon: Users,      color: 'text-slate-500',  gradient: 'from-slate-400 to-slate-600' },
  user:              { icon: Users,      color: 'text-pink-500',   gradient: 'from-pink-500 to-rose-500' },
  supporting_document: { icon: FileText, color: 'text-teal-500',   gradient: 'from-teal-500 to-cyan-500' },
  wiki_section:      { icon: FileText,   color: 'text-purple-500', gradient: 'from-purple-500 to-indigo-500' },
}

const ACTION_LABELS: Record<string, string> = {
  document_reassigned:     'Document reassigned',
  document_deleted:        'Document deleted',
  document_placed:         'Document placed in matter',
  document_processed:      'Document processed',
  matter_created:          'Matter created',
  matter_updated:          'Matter updated',
  matter_deleted:          'Matter deleted',
  client_created:          'Client created',
  client_updated:          'Client updated',
  client_deleted:          'Client deleted',
  link_created:            'Document link created',
  link_deleted:            'Document link deleted',
  link_confirmed:          'Document link confirmed',
  note_created:            'Note added',
  note_deleted:            'Note deleted',
  deadline_created:        'Deadline added',
  deadline_resolved:       'Deadline resolved',
}

const DEADLINE_TYPE_LABELS: Record<string, string> = {
  appeal_window:   'Appeal Window',
  pre_deposit:     'Pre-Deposit',
  hearing_date:    'Hearing Date',
  reply_deadline:  'Reply Deadline',
  stay_application:'Stay Application',
  other:           'Deadline',
}

export function DashboardContent({
  firstName,
  greeting,
  orgName,
  stats,
  needsReviewDocs,
  statCards,
  activityLogs,
  upcomingDeadlines,
}: DashboardContentProps) {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<SearchResultItem[]>([])
  const [isSearching, setIsSearching] = useState(false)
  const [isPending, startTransition] = useTransition()
  
  // Recent Activity Accordion, Filtering & Pagination state
  const [expandedLogId, setExpandedLogId] = useState<string | null>(null)
  const [activitySearch, setActivitySearch] = useState('')
  const [activityEntityFilter, setActivityEntityFilter] = useState('all')
  const [activityPage, setActivityPage] = useState(1)

  const { setBreadcrumbs } = useBreadcrumbs()

  useEffect(() => {
    setBreadcrumbs([])
  }, [setBreadcrumbs])

  useEffect(() => {
    if (!query || query.trim().length < 2) {
      setResults([])
      setIsSearching(false)
      return
    }
    setIsSearching(true)
    const delayDebounce = setTimeout(() => {
      startTransition(async () => {
        try {
          const res = await searchAll(query, false)
          setResults(res)
        } catch (e) {
          console.error(e)
        } finally {
          setIsSearching(false)
        }
      })
    }, 250)

    return () => clearTimeout(delayDebounce)
  }, [query])

  // Filtered Activity Logs
  const filteredLogs = useMemo(() => {
    return (activityLogs || []).filter(log => {
      // Filter by Entity Type
      if (activityEntityFilter !== 'all' && log.entity_type !== activityEntityFilter) {
        return false
      }
      // Filter by Search Query
      if (activitySearch.trim()) {
        const q = activitySearch.toLowerCase()
        const desc = (log.description || '').toLowerCase()
        const action = (log.action || '').toLowerCase()
        const entity = (log.entity_type || '').toLowerCase()
        if (!desc.includes(q) && !action.includes(q) && !entity.includes(q)) {
          return false
        }
      }
      return true
    })
  }, [activityLogs, activityEntityFilter, activitySearch])

  // Pagination for Activity Logs
  const totalPages = Math.max(1, Math.ceil(filteredLogs.length / LOGS_PER_PAGE))
  const paginatedLogs = useMemo(() => {
    const start = (activityPage - 1) * LOGS_PER_PAGE
    return filteredLogs.slice(start, start + LOGS_PER_PAGE)
  }, [filteredLogs, activityPage])

  const toggleLogExpand = (logId: string) => {
    setExpandedLogId(prev => (prev === logId ? null : logId))
  }

  return (
    <div className="flex-1 flex flex-col min-h-0 overflow-y-auto custom-scrollbar animate-fade-in">
      {/* ── Greeting & Search Header ─────────────────────────────── */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-8">
        <div>
          <h1 className="text-2xl font-bold text-[var(--text-primary)] tracking-tight">
            {greeting}, {firstName} 👋
          </h1>
          <p className="text-xs text-[var(--text-muted)] mt-1">
            Overview of <span className="font-semibold text-[var(--text-primary)]">{orgName}</span>
          </p>
        </div>

        {/* Global Search input */}
        <div className="relative w-full md:w-80">
          <div className="relative flex items-center">
            <Search size={15} className="absolute left-3.5 text-[var(--text-muted)] pointer-events-none" />
            <input
              type="text"
              value={query}
              onChange={e => setQuery(e.target.value)}
              placeholder="Search clients, matters, documents..."
              className="w-full h-10 pl-10 pr-9 rounded-xl text-xs bg-[var(--surface)] text-[var(--text-primary)] border border-[var(--border)] focus:border-[var(--primary)] focus:ring-2 focus:ring-[var(--primary)]/20 outline-none transition-all shadow-xs"
            />
            {query && (
              <button
                onClick={() => setQuery('')}
                className="absolute right-3 text-[var(--text-muted)] hover:text-[var(--text-primary)]"
              >
                <X size={14} />
              </button>
            )}
          </div>

          {/* Search Dropdown Results */}
          {query.trim().length >= 2 && (
            <div className="absolute top-12 left-0 right-0 z-50 bg-[var(--surface)] border border-[var(--border)] rounded-xl shadow-xl overflow-hidden max-h-96 overflow-y-auto custom-scrollbar animate-fade-in">
              {isSearching ? (
                <div className="p-4 text-center text-xs text-[var(--text-muted)] flex items-center justify-center gap-2">
                  <Loader2 size={14} className="animate-spin text-[var(--primary)]" />
                  Searching...
                </div>
              ) : results.length === 0 ? (
                <div className="p-4 text-center text-xs text-[var(--text-muted)]">
                  No results found for &quot;{query}&quot;
                </div>
              ) : (
                <div className="divide-y divide-[var(--border)]">
                  {results.map(item => (
                    <Link
                      key={`${item.type}-${item.id}`}
                      href={item.href}
                      onClick={() => setQuery('')}
                      className="flex items-center gap-3 p-3 hover:bg-[var(--surface-hover)] transition-colors"
                    >
                      <div className="w-8 h-8 rounded-lg bg-[var(--bg)] border border-[var(--border)] flex items-center justify-center shrink-0">
                        {item.type === 'client' && <Users size={14} className="text-emerald-500" />}
                        {item.type === 'matter' && <FolderOpen size={14} className="text-indigo-500" />}
                        {item.type === 'document' && <FileText size={14} className="text-blue-500" />}
                      </div>
                      <div className="flex flex-col min-w-0 flex-1">
                        <span className="text-xs font-semibold text-[var(--text-primary)] truncate">{item.title}</span>
                        <span className="text-[10px] text-[var(--text-muted)] truncate">{item.subtitle}</span>
                      </div>
                      <ChevronRight size={14} className="text-[var(--text-muted)] shrink-0" />
                    </Link>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      {/* ── Stat Cards Grid ──────────────────────────────────────── */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        {statCards.map((card, idx) => (
          <Link
            key={idx}
            href={card.href}
            className="group relative p-5 rounded-2xl border border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] transition-all shadow-xs overflow-hidden"
          >
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wider">{card.label}</span>
              <ArrowUpRight size={16} className="text-[var(--text-muted)] group-hover:text-[var(--primary)] group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-all" />
            </div>
            <div className="mt-3 text-3xl font-extrabold text-[var(--text-primary)] tracking-tight">
              {card.value}
            </div>
          </Link>
        ))}
      </div>

      {/* Needs Attention Banner if documents need review */}
      {needsReviewDocs.length > 0 && (
        <div className="mb-8">
          <NeedsAttentionPanel documents={needsReviewDocs} />
        </div>
      )}

      {/* ── Main Dashboard Layout ─────────────────────────────────── */}
      {stats.clients > 0 && (
        <div className="space-y-8 pb-12">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
            {/* Upcoming Deadlines Widget */}
            <div className="lg:col-span-1 flex flex-col rounded-2xl bg-[var(--surface)] border border-[var(--border)] overflow-hidden shadow-xs">
              <div className="flex items-center justify-between px-5 py-4 border-b border-[var(--border)]">
                <div className="flex items-center gap-2.5">
                  <div className="w-8 h-8 rounded-lg bg-rose-500/10 text-rose-600 dark:text-rose-400 border border-rose-500/20 flex items-center justify-center">
                    <Calendar size={15} />
                  </div>
                  <span className="text-sm font-bold text-[var(--text-primary)]">Upcoming Deadlines</span>
                </div>
                <span className="text-xs font-bold px-2 py-0.5 rounded-full bg-rose-500/10 text-rose-600 border border-rose-500/20">
                  {upcomingDeadlines.length}
                </span>
              </div>

              <div className="divide-y divide-[var(--border)] flex-1 overflow-y-auto custom-scrollbar max-h-[420px]">
                {upcomingDeadlines.length === 0 ? (
                  <div className="p-8 text-center text-xs text-[var(--text-muted)]">No upcoming deadlines</div>
                ) : (
                  upcomingDeadlines.map((d: any) => {
                    const days = differenceInDays(new Date(d.due_date), new Date())
                    const urgency = days <= 3 ? 'bg-red-500/10 text-red-600 border border-red-500/20' :
                      days <= 7 ? 'bg-amber-500/10 text-amber-600 border border-amber-500/20' :
                      'bg-blue-500/10 text-blue-600 border border-blue-500/20'

                    return (
                      <div key={d.id} className="p-4 hover:bg-[var(--surface-hover)] transition-colors flex items-start justify-between gap-3">
                        <div className="flex flex-col min-w-0 flex-1">
                          <span className="text-xs font-semibold text-[var(--text-primary)] truncate">
                            {d.title || DEADLINE_TYPE_LABELS[d.deadline_type] || 'Deadline'}
                          </span>
                          <span className="text-[11px] text-[var(--text-muted)] truncate mt-0.5">
                            {d.matters?.clients?.name} · {d.matters?.title}
                          </span>
                        </div>
                        <span className={cn('text-[10px] font-bold px-2 py-0.5 rounded-full shrink-0', urgency)}>
                          {days === 0 ? 'Today' : days === 1 ? '1 day' : `${days}d`}
                        </span>
                      </div>
                    )
                  })
                )}
              </div>
            </div>

            {/* ── Recent Activity Section (Robust Filterable, Paginated, Accordion) ── */}
            <div className="lg:col-span-2 flex flex-col rounded-2xl bg-[var(--surface)] border border-[var(--border)] overflow-hidden shadow-xs">
              {/* Activity Header */}
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 px-5 py-4 border-b border-[var(--border)] shrink-0">
                <div className="flex items-center gap-2.5">
                  <div className="w-8 h-8 rounded-lg bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20 flex items-center justify-center">
                    <Activity size={15} />
                  </div>
                  <span className="text-sm font-bold text-[var(--text-primary)]">Recent Activity</span>
                  <span className="ml-2 flex items-center gap-1.5 text-[10px] font-semibold text-emerald-600 dark:text-emerald-400 bg-emerald-500/10 border border-emerald-500/20 px-2 py-0.5 rounded-full">
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
                    Live
                  </span>
                </div>

                {/* Filter & Search Bar */}
                <div className="flex items-center gap-2">
                  <div className="relative">
                    <Search size={13} className="absolute left-2.5 top-2.5 text-[var(--text-muted)]" />
                    <input
                      type="text"
                      value={activitySearch}
                      onChange={e => { setActivitySearch(e.target.value); setActivityPage(1) }}
                      placeholder="Filter logs..."
                      className="h-8 pl-8 pr-2.5 rounded-lg text-xs bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border)] focus:outline-none focus:ring-1 focus:ring-[var(--primary)] w-36 sm:w-44"
                    />
                  </div>

                  <select
                    value={activityEntityFilter}
                    onChange={e => { setActivityEntityFilter(e.target.value); setActivityPage(1) }}
                    className="h-8 px-2.5 rounded-lg text-xs bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border)] focus:outline-none focus:ring-1 focus:ring-[var(--primary)] cursor-pointer"
                  >
                    <option value="all">All Entities</option>
                    <option value="client">Clients</option>
                    <option value="matter">Matters</option>
                    <option value="document">Documents</option>
                    <option value="case_note">Notes</option>
                    <option value="document_link">Links</option>
                  </select>
                </div>
              </div>

              {/* Activity Log Items (Accordion list — 1 item expanded at a time) */}
              <div className="divide-y divide-[var(--border)] flex-1 min-h-0 overflow-y-auto custom-scrollbar">
                {paginatedLogs.length === 0 ? (
                  <div className="px-5 py-12 text-center text-xs text-[var(--text-muted)]">
                    No activity logs match your filter criteria
                  </div>
                ) : (
                  paginatedLogs.map((log: any) => {
                    const meta = ENTITY_META[log.entity_type] ?? ENTITY_META.document
                    const Icon = meta.icon
                    const label = ACTION_LABELS[log.action] ?? log.action.replace(/_/g, ' ')
                    const isExpanded = expandedLogId === log.id

                    return (
                      <div key={log.id} className="flex flex-col border-b border-[var(--border)] last:border-0 hover:bg-[var(--surface-hover)] transition-colors">
                        <button
                          type="button"
                          onClick={() => toggleLogExpand(log.id)}
                          className="w-full text-left flex items-center justify-between gap-3 px-5 py-3.5 cursor-pointer outline-none"
                        >
                          <div className="flex items-center gap-3 min-w-0 flex-1">
                            <div className={`w-8 h-8 rounded-lg bg-gradient-to-br ${meta.gradient} flex items-center justify-center shrink-0 shadow-xs`}>
                              <Icon size={14} className="text-white" />
                            </div>
                            <div className="flex flex-col min-w-0 flex-1">
                              <span className="text-xs font-semibold text-[var(--text-primary)] truncate">
                                {log.description || label}
                              </span>
                              <span className="text-[11px] text-[var(--text-muted)] mt-0.5 capitalize flex items-center gap-1.5">
                                <span className="font-medium text-[var(--text-secondary)]">{log.entity_type?.replace(/_/g, ' ')}</span>
                                <span>·</span>
                                <span>{label}</span>
                              </span>
                            </div>
                          </div>

                          <div className="flex items-center gap-3 shrink-0 text-xs text-[var(--text-muted)]">
                            <span>{formatDistanceToNow(new Date(log.created_at), { addSuffix: true })}</span>
                            <div className={`w-6 h-6 rounded-md border border-[var(--border)] bg-[var(--bg)] flex items-center justify-center transition-transform ${isExpanded ? 'rotate-90 text-[var(--primary)]' : ''}`}>
                              <ChevronRight size={14} />
                            </div>
                          </div>
                        </button>

                        {/* Accordion Detail Drawer (Expanded View) */}
                        {isExpanded && (
                          <div className="px-5 pb-4 pt-1 animate-in slide-in-from-top-1 fade-in duration-200">
                            <div className="bg-[var(--bg)] border border-[var(--border)] rounded-xl p-4 space-y-3">
                              <div className="flex items-center justify-between text-xs border-b border-[var(--border)] pb-2.5">
                                <span className="font-semibold text-[var(--text-secondary)] flex items-center gap-1.5">
                                  <Info size={13} className="text-[var(--primary)]" />
                                  Log Audit Details
                                </span>
                                <span className="text-[10px] font-mono text-[var(--text-muted)] bg-[var(--surface)] border border-[var(--border)] px-2 py-0.5 rounded">
                                  ID: {log.id}
                                </span>
                              </div>

                              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
                                <div>
                                  <span className="text-[10px] uppercase font-bold text-[var(--text-muted)] tracking-wider">Action</span>
                                  <p className="font-medium text-[var(--text-primary)] mt-0.5">{label}</p>
                                </div>
                                <div>
                                  <span className="text-[10px] uppercase font-bold text-[var(--text-muted)] tracking-wider">Entity Type</span>
                                  <p className="font-medium text-[var(--text-primary)] mt-0.5 capitalize">{log.entity_type?.replace(/_/g, ' ')}</p>
                                </div>
                                {log.entity_id && (
                                  <div>
                                    <span className="text-[10px] uppercase font-bold text-[var(--text-muted)] tracking-wider">Entity Reference</span>
                                    <p className="font-mono text-[11px] text-[var(--text-secondary)] mt-0.5 truncate">{log.entity_id}</p>
                                  </div>
                                )}
                                <div>
                                  <span className="text-[10px] uppercase font-bold text-[var(--text-muted)] tracking-wider">Timestamp</span>
                                  <p className="font-medium text-[var(--text-primary)] mt-0.5">{new Date(log.created_at).toLocaleString()}</p>
                                </div>
                              </div>

                              {/* Metadata Payload if present */}
                              {log.metadata && Object.keys(log.metadata).length > 0 && (
                                <div className="pt-2 border-t border-[var(--border)]">
                                  <span className="text-[10px] uppercase font-bold text-[var(--text-muted)] tracking-wider flex items-center gap-1.5 mb-1.5">
                                    <Code size={12} />
                                    Metadata Payload
                                  </span>
                                  <pre className="text-[11px] font-mono bg-[var(--surface)] border border-[var(--border)] p-2.5 rounded-lg text-[var(--text-secondary)] whitespace-pre-wrap break-all max-h-36 overflow-y-auto custom-scrollbar">
                                    {JSON.stringify(log.metadata, null, 2)}
                                  </pre>
                                </div>
                              )}
                            </div>
                          </div>
                        )}
                      </div>
                    )
                  })
                )}
              </div>

              {/* Activity Pagination Footer */}
              {filteredLogs.length > LOGS_PER_PAGE && (
                <div className="flex items-center justify-between px-5 py-3 border-t border-[var(--border)] shrink-0 text-xs text-[var(--text-muted)] bg-[var(--surface)]">
                  <span>
                    Showing {((activityPage - 1) * LOGS_PER_PAGE) + 1} to {Math.min(activityPage * LOGS_PER_PAGE, filteredLogs.length)} of {filteredLogs.length} logs
                  </span>

                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => setActivityPage(prev => Math.max(1, prev - 1))}
                      disabled={activityPage === 1}
                      className="p-1 px-2.5 rounded-md border border-[var(--border)] bg-[var(--bg)] hover:bg-[var(--surface-hover)] text-[var(--text-primary)] disabled:opacity-40 disabled:cursor-not-allowed flex items-center gap-1"
                    >
                      <ChevronLeft size={13} /> Prev
                    </button>
                    <span className="font-semibold text-[var(--text-primary)]">
                      Page {activityPage} of {totalPages}
                    </span>
                    <button
                      onClick={() => setActivityPage(prev => Math.min(totalPages, prev + 1))}
                      disabled={activityPage === totalPages}
                      className="p-1 px-2.5 rounded-md border border-[var(--border)] bg-[var(--bg)] hover:bg-[var(--surface-hover)] text-[var(--text-primary)] disabled:opacity-40 disabled:cursor-not-allowed flex items-center gap-1"
                    >
                      Next <ChevronRight size={13} />
                    </button>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
