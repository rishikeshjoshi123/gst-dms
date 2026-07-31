'use client'

import { useState, useEffect, useTransition, useMemo } from 'react'
import { searchAll, SearchResultItem } from '@/lib/actions/search'
import { NeedsAttentionPanel } from './NeedsAttentionPanel'
import {
  ArrowUpRight, FileText, Search, Users, FolderOpen, ShieldAlert,
  Loader2, X, Activity, Calendar, Clock, ChevronRight, ChevronLeft,
  Zap, Link2, FileCheck, Info
} from 'lucide-react'
import { cn } from '@/lib/utils'
import Link from 'next/link'
import { formatDistanceToNow, differenceInDays, isToday, isYesterday, differenceInCalendarWeeks } from 'date-fns'
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

/* ─── Stat Card Config with Cool Hover Gradients ─────────────────── */
const STAT_ICONS: Record<string, { icon: React.FC<any>; color: string; bgColor: string; hoverGradient: string; borderHover: string }> = {
  'Active Clients': {
    icon: Users,
    color: 'text-emerald-600 dark:text-emerald-400',
    bgColor: 'bg-emerald-500/10 border border-emerald-500/20',
    hoverGradient: 'hover:bg-gradient-to-br hover:from-emerald-500/10 hover:via-teal-500/5 hover:to-transparent dark:hover:from-emerald-950/40 dark:hover:via-teal-950/20 dark:hover:to-transparent',
    borderHover: 'hover:border-emerald-500/40',
  },
  'Open Matters': {
    icon: FolderOpen,
    color: 'text-indigo-600 dark:text-indigo-400',
    bgColor: 'bg-indigo-500/10 border border-indigo-500/20',
    hoverGradient: 'hover:bg-gradient-to-br hover:from-indigo-500/10 hover:via-purple-500/5 hover:to-transparent dark:hover:from-indigo-950/40 dark:hover:via-purple-950/20 dark:hover:to-transparent',
    borderHover: 'hover:border-indigo-500/40',
  },
  'Documents': {
    icon: FileText,
    color: 'text-blue-600 dark:text-blue-400',
    bgColor: 'bg-blue-500/10 border border-blue-500/20',
    hoverGradient: 'hover:bg-gradient-to-br hover:from-blue-500/10 hover:via-cyan-500/5 hover:to-transparent dark:hover:from-blue-950/40 dark:hover:via-cyan-950/20 dark:hover:to-transparent',
    borderHover: 'hover:border-blue-500/40',
  },
  'Pending Review': {
    icon: ShieldAlert,
    color: 'text-amber-600 dark:text-amber-400',
    bgColor: 'bg-amber-500/10 border border-amber-500/20',
    hoverGradient: 'hover:bg-gradient-to-br hover:from-amber-500/10 hover:via-orange-500/5 hover:to-transparent dark:hover:from-amber-950/40 dark:hover:via-orange-950/20 dark:hover:to-transparent',
    borderHover: 'hover:border-amber-500/40',
  },
}

/* ─── Activity Entity Metadata (Clean SVG Outline icons) ─────────── */
const ENTITY_META: Record<string, { icon: React.FC<any>; color: string }> = {
  document: { icon: FileText, color: 'text-blue-600 dark:text-blue-400' },
  matter: { icon: FolderOpen, color: 'text-indigo-600 dark:text-indigo-400' },
  client: { icon: Users, color: 'text-emerald-600 dark:text-emerald-400' },
  case_note: { icon: FileCheck, color: 'text-violet-600 dark:text-violet-400' },
  document_link: { icon: Link2, color: 'text-amber-600 dark:text-amber-400' },
  deadline: { icon: Calendar, color: 'text-rose-600 dark:text-rose-400' },
  staged_document: { icon: Zap, color: 'text-cyan-600 dark:text-cyan-400' },
  organisation: { icon: Users, color: 'text-slate-600 dark:text-slate-400' },
  user: { icon: Users, color: 'text-pink-600 dark:text-pink-400' },
  supporting_document: { icon: FileText, color: 'text-teal-600 dark:text-teal-400' },
  wiki_section: { icon: FileText, color: 'text-purple-600 dark:text-purple-400' },
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

const LOGS_PER_PAGE = 10

/* ─── Entity navigation helper ──────────────────────────────────── */
function getEntityHref(log: any): string | null {
  if (log.entity_type === 'client' && log.entity_id) return `/clients/${log.entity_id}`
  if (log.entity_type === 'matter' && log.entity_id) return `/matters/${log.entity_id}`
  if (log.entity_type === 'document' && log.entity_id) {
    const matterId = log.metadata?.matter_id
    if (matterId) return `/matters/${matterId}`
  }
  if (log.entity_type === 'document_link') {
    const matterId = log.metadata?.matter_id
    if (matterId) return `/matters/${matterId}`
  }
  return null
}

/* ─── Component ─────────────────────────────────────────────────── */

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

  // Activity state
  const [activitySearch, setActivitySearch] = useState('')
  const [activityEntityFilter, setActivityEntityFilter] = useState('all')
  const [activityTimeFilter, setActivityTimeFilter] = useState('all')
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

  // Filter activity logs (Entity + Time Period + Search)
  const filteredLogs = useMemo(() => {
    return (activityLogs || []).filter(log => {
      // 1. Time filter
      if (activityTimeFilter !== 'all') {
        const d = new Date(log.created_at)
        if (activityTimeFilter === 'today' && !isToday(d)) return false
        if (activityTimeFilter === 'yesterday' && !isYesterday(d)) return false
        if (activityTimeFilter === 'this_week' && differenceInCalendarWeeks(new Date(), d) !== 0) return false
        if (activityTimeFilter === 'older') {
          if (isToday(d) || isYesterday(d) || differenceInCalendarWeeks(new Date(), d) === 0) return false
        }
      }

      // 2. Entity filter
      if (activityEntityFilter !== 'all' && log.entity_type !== activityEntityFilter) return false

      // 3. Search query
      if (activitySearch.trim()) {
        const q = activitySearch.toLowerCase()
        const desc = (log.description || '').toLowerCase()
        const action = (log.action || '').toLowerCase()
        const userEmail = (log.user_email || '').toLowerCase()
        if (!desc.includes(q) && !action.includes(q) && !userEmail.includes(q)) return false
      }
      return true
    })
  }, [activityLogs, activityTimeFilter, activityEntityFilter, activitySearch])

  // Pagination
  const totalPages = Math.max(1, Math.ceil(filteredLogs.length / LOGS_PER_PAGE))
  const paginatedLogs = useMemo(() => {
    const start = (activityPage - 1) * LOGS_PER_PAGE
    return filteredLogs.slice(start, start + LOGS_PER_PAGE)
  }, [filteredLogs, activityPage])

  // Activity summary counts
  const activitySummary = useMemo(() => {
    const todayLogs = (activityLogs || []).filter(l => isToday(new Date(l.created_at)))
    const docsProcessed = todayLogs.filter(l => l.action === 'document_processed').length
    const deadlinesAdded = todayLogs.filter(l => l.action === 'deadline_created').length
    return { total: todayLogs.length, docsProcessed, deadlinesAdded }
  }, [activityLogs])

  return (
    <div className="flex-1 flex flex-col min-h-0 overflow-y-auto custom-scrollbar animate-fade-in">
      {/* ── Greeting & Search Header ──────────────────────────────── */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-8">
        <div>
          <h1 className="text-2xl font-bold text-[var(--text-primary)] tracking-tight">
            {greeting}, {firstName} 👋
          </h1>
          <p className="text-xs text-[var(--text-muted)] mt-1">
            Overview of <span className="font-semibold text-[var(--text-primary)]">{orgName}</span>
          </p>
        </div>

        {/* Global Search */}
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
              <button onClick={() => setQuery('')} className="absolute right-3 text-[var(--text-muted)] hover:text-[var(--text-primary)]">
                <X size={14} />
              </button>
            )}
          </div>

          {/* Search Dropdown */}
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

      {/* ── Stat Cards (Thin, Compact Single-Row Flex Layout) ──────── */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3.5 mb-8">
        {statCards.map((card, idx) => {
          const config = STAT_ICONS[card.label] ?? {
            icon: Info,
            color: 'text-slate-500',
            bgColor: 'bg-slate-500/10 border border-slate-500/20',
            hoverGradient: 'hover:bg-gradient-to-br hover:from-slate-500/10 hover:to-transparent',
            borderHover: 'hover:border-slate-400',
          }
          const Icon = config.icon
          return (
            <Link
              key={idx}
              href={card.href}
              className={cn(
                'group px-4 py-6 rounded-xl border border-[var(--border)] bg-[var(--surface)] transition-all duration-300 shadow-xs hover:shadow-md hover:-translate-y-0.5 flex items-center justify-between gap-3',
                config.hoverGradient,
                config.borderHover
              )}
            >
              <div className="flex items-center gap-3 min-w-0">
                <div className={cn('w-8 h-8 rounded-lg flex items-center justify-center shrink-0', config.bgColor)}>
                  <Icon size={16} className={config.color} />
                </div>
                <div className="flex flex-col min-w-0">
                  <span className="text-[10px] font-bold text-[var(--text-secondary)] uppercase tracking-wider truncate">{card.label}</span>
                  <div className="text-xl font-extrabold text-[var(--text-primary)] tracking-tight leading-none mt-0.5">
                    {card.value}
                  </div>
                </div>
              </div>

              <ArrowUpRight size={15} className="text-[var(--text-muted)] group-hover:text-[var(--primary)] group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-all shrink-0" />
            </Link>
          )
        })}
      </div>

      {/* Needs Attention */}
      {needsReviewDocs.length > 0 && (
        <div className="mb-8">
          <NeedsAttentionPanel documents={needsReviewDocs} />
        </div>
      )}

      {/* ── Empty State (no clients) ──────────────────────────────── */}
      {stats.clients === 0 && (
        <div className="flex-1 flex items-center justify-center pb-12">
          <div className="text-center max-w-md">
            <div className="w-16 h-16 rounded-2xl border border-[var(--border)] bg-[var(--surface)] flex items-center justify-center mx-auto mb-6 shadow-sm">
              <FolderOpen size={28} className="text-[var(--primary)]" />
            </div>
            <h2 className="text-xl font-bold text-[var(--text-primary)] mb-2">Your workspace is ready</h2>
            <p className="text-sm text-[var(--text-secondary)] mb-1">
              Upload documents via the <span className="font-semibold text-[var(--text-primary)]">Document Hub</span> in the sidebar to get started.
            </p>
            <p className="text-xs text-[var(--text-muted)]">
              Clients and matters will be created automatically as documents are processed.
            </p>
          </div>
        </div>
      )}

      {/* ── Main Dashboard Layout ─────────────────────────────────── */}
      {stats.clients > 0 && (
        <div className="space-y-8 pb-12">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
            {/* ── Upcoming Deadlines ──────────────────────────────── */}
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
                            {d.description || DEADLINE_TYPE_LABELS[d.type] || 'Deadline'}
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

            {/* ── Recent Activity (With Time Period Filter & Clean SVG Icons) ─ */}
            <div className="lg:col-span-2 flex flex-col rounded-xl bg-[var(--surface)] border border-[var(--border)] overflow-hidden shadow-xs">
              {/* Activity Header */}
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 px-4 py-3 border-b border-[var(--border)] shrink-0">
                <div className="flex items-center gap-2">
                  <div className="w-6 h-6 rounded-md bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20 flex items-center justify-center">
                    <Activity size={13} />
                  </div>
                  <span className="text-xs font-bold text-[var(--text-primary)]">Recent Activity</span>
                  <span className="ml-1 flex items-center gap-1 text-[10px] font-semibold text-emerald-600 dark:text-emerald-400 bg-emerald-500/10 border border-emerald-500/20 px-1.5 py-0.5 rounded-full">
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse-dot" />
                    Live
                  </span>
                </div>

                {/* Filters Row (Search + Time Period Filter + Entity Filter) */}
                <div className="flex items-center gap-2 flex-wrap sm:flex-nowrap">
                  <div className="relative">
                    <Search size={12} className="absolute left-2.5 top-2 text-[var(--text-muted)]" />
                    <input
                      type="text"
                      value={activitySearch}
                      onChange={e => { setActivitySearch(e.target.value); setActivityPage(1) }}
                      placeholder="Filter logs..."
                      className="h-7 pl-7 pr-2 rounded-md text-[11px] bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border)] focus:outline-none focus:ring-1 focus:ring-[var(--primary)] w-28 sm:w-36"
                    />
                  </div>

                  {/* Time Period Filter Dropdown */}
                  <select
                    value={activityTimeFilter}
                    onChange={e => { setActivityTimeFilter(e.target.value); setActivityPage(1) }}
                    className="h-7 px-2 rounded-md text-[11px] font-medium bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border)] focus:outline-none focus:ring-1 focus:ring-[var(--primary)] cursor-pointer"
                  >
                    <option value="all">All Time</option>
                    <option value="today">Today</option>
                    <option value="yesterday">Yesterday</option>
                    <option value="this_week">This Week</option>
                    <option value="older">Older</option>
                  </select>

                  {/* Entity Filter Dropdown */}
                  <select
                    value={activityEntityFilter}
                    onChange={e => { setActivityEntityFilter(e.target.value); setActivityPage(1) }}
                    className="h-7 px-2 rounded-md text-[11px] font-medium bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border)] focus:outline-none focus:ring-1 focus:ring-[var(--primary)] cursor-pointer"
                  >
                    <option value="all">All Entities</option>
                    <option value="client">Clients</option>
                    <option value="matter">Matters</option>
                    <option value="document">Documents</option>
                    <option value="case_note">Notes</option>
                    <option value="document_link">Links</option>
                    <option value="deadline">Deadlines</option>
                  </select>
                </div>
              </div>

              {/* Activity Summary Strip */}
              {activitySummary.total > 0 && (
                <div className="px-4 py-2 border-b border-[var(--border)] bg-[var(--bg)] text-[11px] text-[var(--text-muted)] flex items-center gap-3">
                  <span className="font-semibold text-[var(--text-secondary)]">{activitySummary.total} actions today</span>
                  {activitySummary.docsProcessed > 0 && (
                    <span>· {activitySummary.docsProcessed} documents processed</span>
                  )}
                  {activitySummary.deadlinesAdded > 0 && (
                    <span>· {activitySummary.deadlinesAdded} deadline{activitySummary.deadlinesAdded > 1 ? 's' : ''} added</span>
                  )}
                </div>
              )}

              {/* Activity Log — Clean continuous list with clean SVG outline icons */}
              <div className="divide-y divide-[var(--border)] flex-1 min-h-0 overflow-y-auto custom-scrollbar">
                {paginatedLogs.length === 0 ? (
                  <div className="px-4 py-8 text-center text-xs text-[var(--text-muted)]">
                    No activity logs match your filter criteria
                  </div>
                ) : (
                  paginatedLogs.map((log: any) => {
                    const meta = ENTITY_META[log.entity_type] ?? ENTITY_META.document
                    const Icon = meta.icon
                    const href = getEntityHref(log)

                    const renderInlineContext = () => {
                      // Document link — show "Linked SCN ↔ Reply"
                      if (log.entity_type === 'document_link' && log.metadata?.from_doc_type) {
                        const isDelete = log.action.includes('deleted')
                        return (
                          <span className="truncate">
                            {isDelete ? 'Unlinked ' : 'Linked '}
                            <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-semibold bg-blue-500/10 text-blue-600 dark:text-blue-400 mx-0.5">
                              {log.metadata.from_doc_type}
                            </span>
                            <span className="text-[var(--text-muted)] mx-0.5">↔</span>
                            <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-semibold bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 mx-0.5">
                              {log.metadata.to_doc_type}
                            </span>
                            {log.metadata.case_name && (
                              <span className="text-[var(--text-muted)]"> in {log.metadata.case_name}</span>
                            )}
                          </span>
                        )
                      }

                      // Document processed — show doc type + ref
                      if (log.action === 'document_processed' && log.description) {
                        const parts = log.description.split(/(\".*?\")/g)
                        if (parts.length > 1) {
                          return (
                            <span className="truncate">
                              {parts.map((part: string, i: number) => {
                                if (part.startsWith('"') && part.endsWith('"')) {
                                  return <span key={i} className="font-semibold text-[var(--primary)]">{part.slice(1, -1)}</span>
                                }
                                return <span key={i}>{part}</span>
                              })}
                            </span>
                          )
                        }
                      }
                      return <span className="truncate">{log.description || ACTION_LABELS[log.action] || log.action}</span>
                    }

                    const content = (
                      <div className="group flex items-center gap-3.5 px-5 py-3 hover:bg-[var(--surface-hover)] transition-colors relative">
                        {/* Left accent */}
                        <div className="absolute left-0 top-0 bottom-0 w-[2px] bg-transparent group-hover:bg-[var(--primary)] transition-colors" />

                        {/* Clean SVG outline Icon container (No solid color filled square!) */}
                        <div className="w-8 h-8 rounded-lg border border-[var(--border-strong)] bg-[var(--bg)] flex items-center justify-center shrink-0 shadow-xs">
                          <Icon size={15} className={meta.color} />
                        </div>

                        {/* Content */}
                        <div className="flex flex-col min-w-0 flex-1">
                          <span className="text-[13px] text-[var(--text-primary)] font-medium truncate">
                            {renderInlineContext()}
                          </span>
                          <span className="text-[11px] text-[var(--text-secondary)] mt-0.5 flex items-center gap-1.5 truncate">
                            <span>{log.user_email || 'System'}</span>
                            <span className="text-[var(--border-strong)]">•</span>
                            <span>{formatDistanceToNow(new Date(log.created_at), { addSuffix: true })}</span>
                          </span>
                        </div>

                        {/* Navigate arrow */}
                        {href && (
                          <ChevronRight size={14} className="text-[var(--text-muted)] shrink-0 opacity-0 group-hover:opacity-100 transition-opacity" />
                        )}
                      </div>
                    )

                    return href ? (
                      <Link key={log.id} href={href} className="block">
                        {content}
                      </Link>
                    ) : (
                      <div key={log.id}>
                        {content}
                      </div>
                    )
                  })
                )}
              </div>

              {/* Pagination Footer */}
              {totalPages > 1 && (
                <div className="px-4 py-2.5 border-t border-[var(--border)] bg-[var(--bg)] flex items-center justify-between text-xs shrink-0">
                  <span className="text-[var(--text-muted)]">
                    Page <span className="font-semibold text-[var(--text-primary)]">{activityPage}</span> of {totalPages}
                  </span>
                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => setActivityPage(p => Math.max(1, p - 1))}
                      disabled={activityPage === 1}
                      className="p-1 rounded border border-[var(--border)] bg-[var(--surface)] text-[var(--text-muted)] hover:text-[var(--text-primary)] disabled:opacity-40 disabled:cursor-not-allowed"
                    >
                      <ChevronLeft size={14} />
                    </button>
                    <button
                      onClick={() => setActivityPage(p => Math.min(totalPages, p + 1))}
                      disabled={activityPage === totalPages}
                      className="p-1 rounded border border-[var(--border)] bg-[var(--surface)] text-[var(--text-muted)] hover:text-[var(--text-primary)] disabled:opacity-40 disabled:cursor-not-allowed"
                    >
                      <ChevronRight size={14} />
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
