'use client'

import { useState, useEffect, useTransition, useMemo } from 'react'
import { searchAll, SearchResultItem } from '@/lib/actions/search'
import { NeedsAttentionPanel } from './NeedsAttentionPanel'
import {
  ArrowUpRight, FileText, Search, Users, FolderOpen, ShieldAlert,
  Loader2, X, Activity, Calendar, Clock, ChevronRight, ChevronLeft,
  Zap, Link2, FileCheck, Info, User
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

const LOGS_PER_PAGE = 10

const ENTITY_META: Record<string, { icon: React.FC<any>; color: string; gradient: string }> = {
  document: { icon: FileText, color: 'text-blue-500', gradient: 'from-blue-500 to-indigo-500' },
  matter: { icon: FolderOpen, color: 'text-indigo-500', gradient: 'from-indigo-500 to-violet-500' },
  client: { icon: Users, color: 'text-emerald-500', gradient: 'from-emerald-500 to-teal-500' },
  case_note: { icon: FileCheck, color: 'text-violet-500', gradient: 'from-violet-500 to-purple-500' },
  document_link: { icon: Link2, color: 'text-amber-500', gradient: 'from-amber-500 to-orange-500' },
  deadline: { icon: Calendar, color: 'text-rose-500', gradient: 'from-rose-500 to-pink-500' },
  staged_document: { icon: Zap, color: 'text-cyan-500', gradient: 'from-cyan-500 to-blue-500' },
  organisation: { icon: Users, color: 'text-slate-500', gradient: 'from-slate-400 to-slate-600' },
  user: { icon: Users, color: 'text-pink-500', gradient: 'from-pink-500 to-rose-500' },
  supporting_document: { icon: FileText, color: 'text-teal-500', gradient: 'from-teal-500 to-cyan-500' },
  wiki_section: { icon: FileText, color: 'text-purple-500', gradient: 'from-purple-500 to-indigo-500' },
}

const ACTION_LABELS: Record<string, string> = {
  document_reassigned: 'Document reassigned',
  document_deleted: 'Document deleted',
  document_placed: 'Document placed in matter',
  document_processed: 'Document processed',
  matter_created: 'Matter created',
  matter_updated: 'Matter updated',
  matter_deleted: 'Matter deleted',
  client_created: 'Client created',
  client_updated: 'Client updated',
  client_deleted: 'Client deleted',
  manual_link_created: 'Manual link created',
  manual_link_deleted: 'Manual link deleted',
  link_created: 'Document link created',
  link_deleted: 'Document link deleted',
  link_confirmed: 'Document link confirmed',
  note_created: 'Note added',
  note_deleted: 'Note deleted',
  deadline_created: 'Deadline added',
  deadline_resolved: 'Deadline resolved',
}

const DEADLINE_TYPE_LABELS: Record<string, string> = {
  appeal_window: 'Appeal Window',
  pre_deposit: 'Pre-Deposit',
  hearing_date: 'Hearing Date',
  reply_deadline: 'Reply Deadline',
  stay_application: 'Stay Application',
  other: 'Deadline',
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
      if (activityEntityFilter !== 'all' && log.entity_type !== activityEntityFilter) {
        return false
      }
      if (activitySearch.trim()) {
        const q = activitySearch.toLowerCase()
        const desc = (log.description || '').toLowerCase()
        const action = (log.action || '').toLowerCase()
        const userEmail = (log.user_email || '').toLowerCase()
        if (!desc.includes(q) && !action.includes(q) && !userEmail.includes(q)) {
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

      {/* ── Stat Cards Grid ── */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        {statCards.map((card, idx) => (
          <Link
            key={idx}
            href={card.href}
            className="group p-5 rounded-xl border border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] transition-all shadow-xs"
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
            <div className="lg:col-span-1 flex flex-col rounded-xl bg-[var(--surface)] border border-[var(--border)] overflow-hidden shadow-xs">
              <div className="flex items-center justify-between px-5 py-3.5 border-b border-[var(--border)]">
                <div className="flex items-center gap-2.5">
                  <div className="w-7 h-7 rounded-lg bg-rose-500/10 text-rose-600 dark:text-rose-400 border border-rose-500/20 flex items-center justify-center">
                    <Calendar size={14} />
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
                      <div key={d.id} className="p-3.5 hover:bg-[var(--surface-hover)] transition-colors flex items-start justify-between gap-3">
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

            {/* ── Recent Activity Section (Compact Thin Rows, User Mentions, Accordion, Filters) ── */}
            <div className="lg:col-span-2 flex flex-col rounded-xl bg-[var(--surface)] border border-[var(--border)] overflow-hidden shadow-xs">
              {/* Activity Header */}
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 px-4 py-3 border-b border-[var(--border)] shrink-0">
                <div className="flex items-center gap-2">
                  <div className="w-6 h-6 rounded-md bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20 flex items-center justify-center">
                    <Activity size={13} />
                  </div>
                  <span className="text-xs font-bold text-[var(--text-primary)]">Recent Activity</span>
                  <span className="ml-1 flex items-center gap-1 text-[10px] font-semibold text-emerald-600 dark:text-emerald-400 bg-emerald-500/10 border border-emerald-500/20 px-1.5 py-0.2 rounded-full">
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
                    Live
                  </span>
                </div>

                {/* Filter & Search Controls */}
                <div className="flex items-center gap-2">
                  <div className="relative">
                    <Search size={12} className="absolute left-2.5 top-2 text-[var(--text-muted)]" />
                    <input
                      type="text"
                      value={activitySearch}
                      onChange={e => { setActivitySearch(e.target.value); setActivityPage(1) }}
                      placeholder="Filter logs..."
                      className="h-7 pl-7 pr-2 rounded-md text-[11px] bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border)] focus:outline-none focus:ring-1 focus:ring-[var(--primary)] w-32 sm:w-40"
                    />
                  </div>

                  <select
                    value={activityEntityFilter}
                    onChange={e => { setActivityEntityFilter(e.target.value); setActivityPage(1) }}
                    className="h-7 px-2 rounded-md text-[11px] bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border)] focus:outline-none focus:ring-1 focus:ring-[var(--primary)] cursor-pointer"
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

              {/* Activity Log Compact Thin Rows */}
              <div className="divide-y divide-[var(--border)] flex-1 min-h-0 overflow-y-auto custom-scrollbar">
                {paginatedLogs.length === 0 ? (
                  <div className="px-4 py-8 text-center text-xs text-[var(--text-muted)]">
                    No activity logs match your filter criteria
                  </div>
                ) : (
                  paginatedLogs.map((log: any) => {
                    const meta = ENTITY_META[log.entity_type] ?? ENTITY_META.document
                    const Icon = meta.icon
                    const label = ACTION_LABELS[log.action] ?? log.action.replace(/_/g, ' ')
                    const isExpanded = expandedLogId === log.id
                    const userMention = log.user_email || 'System'
                    const hasDetails = !!log.metadata?.from_doc_type

                    const renderRichTitle = () => {
                      if (log.entity_type === 'document_link' && log.metadata?.from_doc_type) {
                        const isDelete = log.action.includes('deleted')
                        const actionText = isDelete ? 'Deleted link between ' : 'Manually linked '
                        return (
                          <span className="truncate">
                            <span>{actionText}</span>
                            <span className="font-semibold ">{log.metadata.from_doc_type}</span>
                            <span> and </span>
                            <span className="font-semibold">{log.metadata.to_doc_type}</span>
                            <span> in </span>
                            <span className="font-semibold">{log.metadata.case_name}</span>
                          </span>
                        )
                      }

                      const text = log.description || label
                      const parts = text.split(/(".*?")/g)
                      if (parts.length > 1) {
                        return (
                          <span className="truncate">
                            {parts.map((part: string, i: number) => {
                              if (part.startsWith('"') && part.endsWith('"')) {
                                return <span key={i} className="text-[var(--primary)] font-bold">{part.slice(1, -1)}</span>
                              }
                              return <span key={i}>{part}</span>
                            })}
                          </span>
                        )
                      }
                      return <span className="truncate">{text}</span>
                    }

                    return (
                      <div key={log.id} className="group flex flex-col border-b border-[var(--border)] last:border-0 hover:bg-[var(--surface-hover)] transition-colors relative">
                        <div className="absolute left-0 top-0 bottom-0 w-[2px] bg-transparent group-hover:bg-[var(--primary)] transition-colors" />

                        <div
                          onClick={() => hasDetails && toggleLogExpand(log.id)}
                          className={`w-full text-left flex items-center justify-between gap-4 px-5 py-3 outline-none ${hasDetails ? 'cursor-pointer' : 'cursor-default'}`}
                        >
                          <div className="flex items-center gap-3.5 min-w-0 flex-1">
                            <div className={`w-8 h-8 rounded-lg bg-gradient-to-br ${meta.gradient} flex items-center justify-center shrink-0 shadow-xs`}>
                              <Icon size={14} className="text-white" />
                            </div>
                            <div className="flex flex-col min-w-0 flex-1">
                              <span className="text-[13px] text-[var(--text-primary)] truncate">
                                {renderRichTitle()}
                              </span>
                              <span className="text-[11px] text-[var(--text-secondary)] mt-0.5 flex items-center gap-1.5 truncate">
                                <span>{userMention}</span>
                                <span className="text-[var(--border-strong)]">•</span>
                                <span>{formatDistanceToNow(new Date(log.created_at), { addSuffix: true })}</span>
                              </span>
                            </div>
                          </div>

                          {hasDetails && (
                            <div className="flex items-center gap-2 shrink-0">
                              <div className={`w-6 h-6 rounded-md border border-transparent group-hover:border-[var(--border)] group-hover:bg-[var(--bg)] flex items-center justify-center transition-all ${isExpanded ? 'rotate-90 text-[var(--primary)]' : 'text-[var(--text-muted)]'}`}>
                                <ChevronRight size={14} />
                              </div>
                            </div>
                          )}
                        </div>

                        {/* Accordion Detail Drawer (Premium Inset) */}
                        {hasDetails && isExpanded && (
                          <div className="pl-[60px] pr-5 pb-3 pt-0 animate-in slide-in-from-top-1 fade-in duration-200">
                            <div className="bg-[var(--bg)] border border-[var(--border)] rounded-md p-3 text-[12px] shadow-inner shadow-[var(--border)]/10">
                              {/* Document Link Context Details */}
                              <div className="text-[var(--text-secondary)] flex items-center gap-2">
                                <Link2 size={14} className="text-[var(--primary)] shrink-0" />
                                <span>
                                  {log.action.includes('deleted') ? 'Unlinked' : 'Linked'} <strong className="text-[var(--text-primary)] font-semibold">{log.metadata.from_doc_type} ({log.metadata.from_ref || 'N/A'})</strong> and <strong className="text-[var(--text-primary)] font-semibold">{log.metadata.to_doc_type} ({log.metadata.to_ref || 'N/A'})</strong>
                                </span>
                              </div>
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
                <div className="flex items-center justify-between px-3 py-1.5 border-t border-[var(--border)] shrink-0 text-[11px] text-[var(--text-muted)] bg-[var(--surface)]">
                  <span>
                    Showing {((activityPage - 1) * LOGS_PER_PAGE) + 1} to {Math.min(activityPage * LOGS_PER_PAGE, filteredLogs.length)} of {filteredLogs.length} logs
                  </span>

                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => setActivityPage(prev => Math.max(1, prev - 1))}
                      disabled={activityPage === 1}
                      className="p-1 px-2 rounded border border-[var(--border)] bg-[var(--bg)] hover:bg-[var(--surface-hover)] text-[var(--text-primary)] disabled:opacity-40 disabled:cursor-not-allowed flex items-center gap-1"
                    >
                      <ChevronLeft size={12} /> Prev
                    </button>
                    <span className="font-semibold text-[var(--text-primary)]">
                      Page {activityPage} of {totalPages}
                    </span>
                    <button
                      onClick={() => setActivityPage(prev => Math.min(totalPages, prev + 1))}
                      disabled={activityPage === totalPages}
                      className="p-1 px-2 rounded border border-[var(--border)] bg-[var(--surface-hover)] text-[var(--text-primary)] disabled:opacity-40 disabled:cursor-not-allowed flex items-center gap-1"
                    >
                      Next <ChevronRight size={12} />
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
