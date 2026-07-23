'use client'

import { useState, useEffect, useTransition } from 'react'
import { searchAll, SearchResultItem } from '@/lib/actions/search'
import { NeedsAttentionPanel } from './NeedsAttentionPanel'
import {
  ArrowUpRight, FileText, Search, Users, FolderOpen,
  Loader2, X, Activity, Calendar, Clock, ChevronRight, ChevronDown,
  AlertCircle, Zap, Link2, FileCheck, ShieldAlert, Code
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
  const [expandedLogs, setExpandedLogs] = useState<Set<string>>(new Set())

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

  const handleSemanticSearch = () => {
    if (!query || query.trim().length < 2) return
    setIsSearching(true)
    startTransition(async () => {
      try {
        const res = await searchAll(query, true)
        setResults(res)
      } catch (e) {
        console.error(e)
      } finally {
        setIsSearching(false)
      }
    })
  }

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') { e.preventDefault(); handleSemanticSearch() }
  }

  const toggleLogExpand = (id: string) => {
    setExpandedLogs(prev => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const clients = results.filter(r => r.type === 'client')
  const matters = results.filter(r => r.type === 'matter')
  const documents = results.filter(r => r.type === 'document')
  const showResults = query.trim().length >= 2

  const pendingReviewCount = needsReviewDocs.length

  return (
    <div className="flex flex-col flex-1 overflow-y-auto pr-1 custom-scrollbar">
      {/* Page header + search */}
      <div className="mb-6 animate-fade-in flex flex-col md:flex-row md:items-center md:justify-between gap-4 shrink-0">
        <div>
          <h1 className="text-2xl font-bold text-[var(--text-primary)] tracking-tight">
            {greeting}, {firstName} 👋
          </h1>
          <p className="mt-0.5 text-sm text-[var(--text-muted)]">
            Welcome to <span className="text-[var(--text-secondary)] font-semibold">{orgName}</span> workspace
          </p>
        </div>
        <div className="relative w-full md:max-w-xl">
          <Search size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-[var(--text-muted)] pointer-events-none" />
          <input
            type="text"
            placeholder="Search clients, matters, documents..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            className="w-full h-10 pl-10 pr-24 rounded-xl text-sm bg-[var(--surface)] text-[var(--text-primary)] placeholder:text-[var(--text-muted)] border border-[var(--border-strong)] focus:border-[var(--primary)] focus:ring-2 focus:ring-[var(--primary)]/20 outline-none transition-all shadow-sm"
          />
          <div className="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-1 text-[10px] text-[var(--text-muted)] bg-[var(--surface-hover)] border border-[var(--border)] px-1.5 py-0.5 rounded pointer-events-none">
            <span className="font-semibold">Enter</span> for deep search
          </div>
          {query && (
            <button
              onClick={() => setQuery('')}
              className="absolute right-28 top-1/2 -translate-y-1/2 p-1 text-[var(--text-muted)] hover:text-[var(--text-primary)] rounded-full hover:bg-[var(--surface-hover)] transition-colors"
            >
              <X size={14} />
            </button>
          )}
        </div>
      </div>

      {showResults ? (
        /* ── Search results ── */
        <div className="mt-2 animate-fade-in">
          {isPending || (query.trim().length >= 2 && results.length === 0 && isSearching) ? (
            <div className="flex flex-col items-center justify-center py-20 text-[var(--text-muted)] gap-3">
              <Loader2 size={24} className="animate-spin text-[var(--primary)]" />
              <p className="text-sm">Searching...</p>
            </div>
          ) : results.length === 0 ? (
            <div className="rounded-xl bg-[var(--surface)] border border-[var(--border)] p-12 text-center shadow-sm">
              <p className="text-sm text-[var(--text-muted)]">
                No results for &ldquo;<span className="text-[var(--text-primary)] font-semibold">{query}</span>&rdquo;
              </p>
            </div>
          ) : (
            <div className="flex flex-col gap-6">
              <div className="flex items-center justify-between border-b border-[var(--border)] pb-3">
                <h2 className="text-base font-semibold text-[var(--text-primary)]">
                  Results for &ldquo;{query}&rdquo;
                </h2>
                <span className="text-xs text-[var(--text-muted)] uppercase tracking-wider font-medium">
                  {results.length} match{results.length !== 1 && 'es'}
                </span>
              </div>

              {[
                { label: 'Clients', items: clients, iconBg: 'bg-blue-500/10', icon: <Users size={16} className="text-blue-500" /> },
                { label: 'Matters', items: matters, iconBg: 'bg-amber-500/10', icon: <FolderOpen size={16} className="text-amber-500" /> },
                { label: 'Documents', items: documents, iconBg: 'bg-slate-500/10', icon: <FileText size={16} className="text-slate-500" /> },
              ].map(({ label, items, iconBg, icon }) => items.length > 0 && (
                <div key={label}>
                  <h3 className="text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide mb-2.5">
                    {label} ({items.length})
                  </h3>
                  <div className="flex flex-col gap-2">
                    {items.map(item => (
                      <Link key={item.id} href={item.href}
                        className="group flex items-center justify-between p-3 rounded-xl bg-[var(--surface)] border border-[var(--border)] hover:border-[var(--border-strong)] hover:shadow-sm transition-all"
                      >
                        <div className="flex items-center gap-3">
                          <div className={`w-8 h-8 rounded-lg ${iconBg} flex items-center justify-center shrink-0`}>{icon}</div>
                          <div>
                            <p className="text-sm font-medium text-[var(--text-primary)]">{item.title}</p>
                            <p className="text-xs text-[var(--text-muted)]">{item.subtitle}</p>
                          </div>
                        </div>
                        <ArrowUpRight size={16} className="text-[var(--text-muted)] group-hover:text-[var(--primary)] group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-all" />
                      </Link>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      ) : (
        /* ── Default Dashboard ── */
        <div className="animate-fade-in flex flex-col gap-6">

          {/* Stat cards */}
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
            {statCards.map(({ label, value, href }) => {
              const isPendingReview = label === 'Pending Review'
              const theme =
                label === 'Open Matters' ? { icon: FolderOpen, gradient: 'from-indigo-500/10 to-transparent', iconBg: 'bg-indigo-600 shadow-indigo-500/25' } :
                label === 'Documents'    ? { icon: FileText,   gradient: 'from-emerald-500/10 to-transparent', iconBg: 'bg-emerald-600 shadow-emerald-500/25' } :
                isPendingReview         ? { icon: ShieldAlert,  gradient: 'from-amber-500/10 to-transparent', iconBg: 'bg-amber-500 shadow-amber-500/25' } :
                                          { icon: Users,       gradient: 'from-blue-500/10 to-transparent', iconBg: 'bg-blue-600 shadow-blue-500/25' }
              const IconComp = theme.icon
              const cardHref = isPendingReview ? '/review' : href

              return (
                <Link
                  key={label}
                  href={cardHref}
                  className="group relative flex flex-col justify-between p-5 rounded-xl bg-[var(--surface)] border border-[var(--border)] hover:border-[var(--border-strong)] hover:shadow-lg hover:-translate-y-0.5 transition-all duration-300 overflow-hidden"
                >
                  <div className={`absolute inset-0 bg-gradient-to-br ${theme.gradient} opacity-60 group-hover:opacity-100 transition-opacity`} />
                  <div className="relative z-10 flex items-center justify-between mb-4">
                    <div className={`flex items-center justify-center h-10 w-10 rounded-xl ${theme.iconBg} text-white shadow-md`}>
                      <IconComp size={20} />
                    </div>
                    <ArrowUpRight size={16} className="text-[var(--text-muted)] group-hover:text-[var(--primary)] group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-all" />
                  </div>
                  <div className="relative z-10">
                    <span className="text-[11px] font-bold uppercase tracking-wider text-[var(--text-muted)] block mb-1">{label}</span>
                    <div className="flex items-baseline justify-between">
                      <span className="text-3xl font-extrabold text-[var(--text-primary)] tracking-tight">{value}</span>
                      {isPendingReview && value > 0 && (
                        <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300 animate-pulse">
                          Action needed
                        </span>
                      )}
                    </div>
                  </div>
                </Link>
              )
            })}
          </div>

          {/* Needs Attention */}
          <NeedsAttentionPanel documents={needsReviewDocs} />

          {/* Deadlines + Activity — 2 column layout */}
          <div className="grid grid-cols-1 lg:grid-cols-5 gap-5">

            {/* Upcoming Deadlines */}
            <div className="lg:col-span-2 rounded-xl bg-[var(--surface)] border border-[var(--border)] overflow-hidden">
              <div className="flex items-center justify-between px-5 py-3.5 border-b border-[var(--border)]">
                <div className="flex items-center gap-2.5">
                  <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-rose-500 to-pink-500 flex items-center justify-center">
                    <Calendar size={13} className="text-white" />
                  </div>
                  <span className="text-sm font-bold text-[var(--text-primary)]">Upcoming Deadlines</span>
                </div>
                <Link href="/matters" className="text-xs text-[var(--primary)] hover:underline font-medium">
                  All matters
                </Link>
              </div>
              <div className="divide-y divide-[var(--border)]">
                {upcomingDeadlines.length === 0 ? (
                  <div className="px-5 py-10 text-center text-sm text-[var(--text-muted)]">No upcoming deadlines</div>
                ) : (
                  upcomingDeadlines.map((d: any) => {
                    const days = differenceInDays(new Date(d.due_date), new Date())
                    const urgency = days <= 3 ? 'text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-950/40' :
                                    days <= 7 ? 'text-amber-600 dark:text-amber-400 bg-amber-50 dark:bg-amber-950/40' :
                                                'text-emerald-600 dark:text-emerald-400 bg-emerald-50 dark:bg-emerald-950/40'
                    return (
                      <div key={d.id} className="flex items-center gap-3 px-5 py-3 hover:bg-[var(--surface-hover)] transition-colors">
                        <div className="flex-1 min-w-0">
                          <p className="text-xs font-semibold text-[var(--text-primary)] truncate">
                            {DEADLINE_TYPE_LABELS[d.type] ?? d.type}
                          </p>
                          <p className="text-[11px] text-[var(--text-muted)] truncate mt-0.5">
                            {d.matters?.clients?.name} · {d.matters?.title}
                          </p>
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

            {/* Live Activity Feed */}
            <div className="lg:col-span-3 rounded-xl bg-[var(--surface)] border border-[var(--border)] overflow-hidden">
              <div className="flex items-center gap-2.5 px-5 py-3.5 border-b border-[var(--border)]">
                <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-blue-500 to-indigo-500 flex items-center justify-center">
                  <Activity size={13} className="text-white" />
                </div>
                <span className="text-sm font-bold text-[var(--text-primary)]">Recent Activity</span>
                <span className="ml-auto flex items-center gap-1.5 text-[10px] font-semibold text-emerald-600 dark:text-emerald-400">
                  <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
                  Live
                </span>
              </div>
              <div className="divide-y divide-[var(--border)]">
                {activityLogs.length === 0 ? (
                  <div className="px-5 py-10 text-center text-sm text-[var(--text-muted)]">No activity yet</div>
                ) : (
                  activityLogs.slice(0, 10).map((log: any) => {
                    const meta = ENTITY_META[log.entity_type] ?? ENTITY_META.document
                    const Icon = meta.icon
                    const label = ACTION_LABELS[log.action] ?? log.action.replace(/_/g, ' ')
                    const isExpanded = expandedLogs.has(log.id)
                    const hasMetadata = log.metadata && Object.keys(log.metadata).length > 0

                    return (
                      <div key={log.id} className="flex flex-col border-b border-[var(--border)] last:border-0 hover:bg-[var(--surface-hover)] transition-colors">
                        <div 
                          className={`flex items-center gap-3 px-5 py-3 ${hasMetadata ? 'cursor-pointer' : ''}`}
                          onClick={() => hasMetadata && toggleLogExpand(log.id)}
                        >
                          <div className={`w-7 h-7 rounded-lg bg-gradient-to-br ${meta.gradient} flex items-center justify-center shrink-0`}>
                            <Icon size={12} className="text-white" />
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="text-xs font-medium text-[var(--text-primary)] truncate">
                              {log.description || label}
                            </p>
                            <p className="text-[11px] text-[var(--text-muted)] mt-0.5 capitalize flex items-center gap-2">
                              <span>{log.entity_type?.replace(/_/g, ' ')}</span>
                            </p>
                          </div>
                          <span className="text-[11px] text-[var(--text-muted)] whitespace-nowrap shrink-0 flex items-center gap-2">
                            {formatDistanceToNow(new Date(log.created_at), { addSuffix: true })}
                            {hasMetadata && (
                              isExpanded ? <ChevronDown size={14} className="text-[var(--text-muted)]" /> : <ChevronRight size={14} className="text-[var(--text-disabled)]" />
                            )}
                          </span>
                        </div>
                        {isExpanded && hasMetadata && (
                          <div className="px-5 pb-4 animate-in slide-in-from-top-1 fade-in duration-200">
                            <div className="bg-[var(--bg)] border border-[var(--border)] rounded-lg p-3">
                              <div className="flex items-center gap-2 mb-2 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
                                <Code size={12} />
                                Metadata Payload
                              </div>
                              <pre className="text-[11px] font-mono text-[var(--text-secondary)] whitespace-pre-wrap break-all custom-scrollbar overflow-y-auto max-h-40">
                                {JSON.stringify(log.metadata, null, 2)}
                              </pre>
                            </div>
                          </div>
                        )}
                      </div>
                    )
                  })
                )}
              </div>
            </div>
          </div>

          {/* Getting started — only shown when empty */}
          {stats.clients === 0 && (
            <div className="rounded-xl bg-[var(--surface)] border border-[var(--border)] p-8 text-center shadow-sm">
              <div className="mx-auto mb-4 w-14 h-14 rounded-2xl bg-gradient-to-br from-blue-500 to-indigo-500 flex items-center justify-center">
                <FileText size={24} className="text-white" />
              </div>
              <h2 className="text-lg font-bold text-[var(--text-primary)]">Welcome to GST DMS</h2>
              <p className="mt-2 text-sm text-[var(--text-muted)] max-w-sm mx-auto leading-relaxed">
                Your workspace is ready. Start by adding your first client to begin tracking their matters.
              </p>
              <div className="mt-6 flex justify-center gap-3">
                <Link
                  href="/clients"
                  className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl bg-gradient-to-r from-blue-600 to-indigo-600 text-white text-sm font-medium hover:opacity-90 transition-opacity shadow-md shadow-blue-500/25"
                >
                  Add your first client
                  <ArrowUpRight size={14} />
                </Link>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
