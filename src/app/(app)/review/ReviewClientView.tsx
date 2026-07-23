'use client'

import { useState, useTransition } from 'react'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { toast } from 'sonner'
import { dismissReviewFlag } from '@/lib/actions/document'
import { useRouter } from 'next/navigation'
import {
  AlertTriangle, Link2, CheckSquare, Inbox,
  FileText, FolderOpen, ExternalLink, Check, X,
  Clock, ChevronRight, ShieldAlert
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { formatDistanceToNow } from 'date-fns'

type Section = 'docs' | 'links' | 'tasks' | 'staged'

const SECTION_META = {
  docs: {
    icon: AlertTriangle,
    color: 'text-amber-600 dark:text-amber-500',
    activeBorder: 'border-amber-500',
    label: 'Documents Needing Review',
    desc: 'Documents the engine could not automatically place or classify',
    emptyText: 'No documents need manual review',
  },
  links: {
    icon: Link2,
    color: 'text-violet-600 dark:text-violet-500',
    activeBorder: 'border-violet-500',
    label: 'Low-Confidence Links',
    desc: 'Document relationships suggested by the engine with confidence below 70%',
    emptyText: 'No pending link suggestions',
  },
  tasks: {
    icon: CheckSquare,
    color: 'text-blue-600 dark:text-blue-500',
    activeBorder: 'border-blue-500',
    label: 'Open Action Items',
    desc: 'Unresolved tasks from case notes assigned across matters',
    emptyText: 'No open action items',
  },
  staged: {
    icon: Inbox,
    color: 'text-emerald-600 dark:text-emerald-500',
    activeBorder: 'border-emerald-500',
    label: 'Staged Documents',
    desc: 'Documents analysed by the engine but not yet assigned to a matter',
    emptyText: 'No staged documents waiting',
  },
} as const

export function ReviewClientView({
  needsReviewDocs,
  pendingLinks,
  openTasks,
  stagedDocs,
}: {
  needsReviewDocs: any[]
  pendingLinks: any[]
  openTasks: any[]
  stagedDocs: any[]
}) {
  const router = useRouter()
  const [activeSection, setActiveSection] = useState<Section>('docs')
  const [dismissedDocs, setDismissedDocs] = useState<Set<string>>(new Set())
  const [isPending, startTransition] = useTransition()

  const totalItems = needsReviewDocs.length + pendingLinks.length + openTasks.length + stagedDocs.length

  const sections: { key: Section; count: number }[] = [
    { key: 'docs', count: needsReviewDocs.filter(d => !dismissedDocs.has(d.id)).length },
    { key: 'links', count: pendingLinks.length },
    { key: 'tasks', count: openTasks.length },
    { key: 'staged', count: stagedDocs.length },
  ]

  function handleDismissDoc(id: string) {
    startTransition(async () => {
      const res = await dismissReviewFlag(id)
      if ('error' in res && res.error) { toast.error(res.error as string); return }
      setDismissedDocs(prev => new Set([...prev, id]))
      toast.success('Document dismissed from review queue')
    })
  }

  return (
    <div className="flex flex-col flex-1 overflow-hidden animate-fade-in">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Pending Review' }]} />

      {/* Header */}
      <div className="shrink-0 pb-5">
        <div className="flex items-start gap-4">
          <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-amber-500 to-orange-500 flex items-center justify-center shadow-lg shadow-amber-500/25 shrink-0">
            <ShieldAlert size={22} className="text-white" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-[var(--text-primary)] tracking-tight">Pending Review</h1>
            <p className="text-sm text-[var(--text-muted)] mt-0.5">
              {totalItems > 0
                ? `${totalItems} item${totalItems !== 1 ? 's' : ''} across ${sections.filter(s => s.count > 0).length} categories need your attention`
                : 'Everything is clear — nothing pending review'}
            </p>
          </div>
        </div>
      </div>

      <div className="flex flex-col flex-1 min-h-0">
        {/* Horizontal Tabs nav */}
        <div className="flex items-center gap-1 border-b border-[var(--border-strong)] mb-5 overflow-x-auto custom-scrollbar shrink-0 px-1">
          {sections.map(({ key, count }) => {
            const meta = SECTION_META[key]
            const Icon = meta.icon
            const isActive = activeSection === key
            return (
              <button
                key={key}
                onClick={() => setActiveSection(key)}
                className={cn(
                  'flex items-center gap-2 px-4 py-3 border-b-2 transition-all shrink-0',
                  isActive
                    ? `border-[var(--primary)] text-[var(--text-primary)] font-medium`
                    : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--surface-hover)]'
                )}
              >
                <Icon size={16} className={isActive ? meta.color : ''} />
                <span className="text-sm whitespace-nowrap">{meta.label}</span>
                {count > 0 && (
                  <span className={cn(
                    'text-[10px] font-bold px-1.5 py-0.5 rounded-full ml-1',
                    isActive
                      ? 'bg-[var(--primary)] text-white'
                      : 'bg-[var(--surface-hover)] border border-[var(--border)] text-[var(--text-secondary)]'
                  )}>
                    {count}
                  </span>
                )}
              </button>
            )
          })}
        </div>

        {/* Main content */}
        <div className="flex-1 min-w-0 overflow-y-auto custom-scrollbar pr-2">
          {(() => {
            const meta = SECTION_META[activeSection]

            if (activeSection === 'docs') {
              const visible = needsReviewDocs.filter(d => !dismissedDocs.has(d.id))
              return (
                <SectionWrapper meta={meta} count={visible.length}>
                  {visible.length === 0 ? (
                    <EmptyState text={meta.emptyText} />
                  ) : (
                    visible.map(doc => (
                      <div key={doc.id} className="group relative flex items-start gap-4 p-5 rounded-xl border border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] hover:shadow-[var(--shadow-md)] transition-all duration-300 overflow-hidden">
                        <div className="absolute top-0 right-0 w-32 h-32 bg-gradient-to-bl from-amber-500/5 to-transparent rounded-bl-full pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity" />
                        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-amber-50 to-orange-50 dark:from-amber-950/30 dark:to-orange-950/30 border border-amber-200 dark:border-amber-900/50 flex items-center justify-center shrink-0 relative z-10">
                          <FileText size={18} className="text-amber-600 dark:text-amber-500" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            <p className="font-semibold text-sm text-[var(--text-primary)] truncate">
                              {doc.doc_type || doc.storage_path?.split('/').pop() || 'Unknown document'}
                            </p>
                            {doc.reference_number && (
                              <span className="text-[10px] font-mono bg-[var(--bg)] border border-[var(--border)] px-1.5 py-0.5 rounded text-[var(--text-muted)] shrink-0">
                                {doc.reference_number}
                              </span>
                            )}
                          </div>
                          {doc.review_reason && (
                            <p className="text-xs text-[var(--text-muted)] mb-2 line-clamp-2">{doc.review_reason}</p>
                          )}
                          {doc.matters && (
                            <div className="flex items-center gap-1.5 text-xs text-[var(--text-muted)]">
                              <FolderOpen size={11} />
                              <span>{doc.matters.clients?.name} · {doc.matters.title}</span>
                            </div>
                          )}
                        </div>
                        <div className="flex items-center gap-2 shrink-0">
                          <button
                            onClick={() => handleDismissDoc(doc.id)}
                            disabled={isPending}
                            className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-medium text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--surface-hover)] border border-[var(--border)] transition-colors"
                          >
                            <X size={12} />
                            Dismiss
                          </button>
                          {doc.matters?.id && (
                            <a
                              href={`/matters/${doc.matters.id}`}
                              className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-medium bg-gradient-to-r from-blue-600 to-indigo-600 text-white hover:opacity-90 transition-opacity"
                            >
                              View <ChevronRight size={12} />
                            </a>
                          )}
                        </div>
                      </div>
                    ))
                  )}
                </SectionWrapper>
              )
            }

            if (activeSection === 'links') {
              return (
                <SectionWrapper meta={meta} count={pendingLinks.length}>
                  {pendingLinks.length === 0 ? (
                    <EmptyState text={meta.emptyText} />
                  ) : (
                    pendingLinks.map((link: any) => {
                      const confidence = link.confidence ? Math.round(link.confidence * 100) : null
                      return (
                        <div key={link.id} className="group relative flex items-start gap-4 p-5 rounded-xl border border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] hover:shadow-[var(--shadow-md)] transition-all duration-300 overflow-hidden">
                          <div className="absolute top-0 right-0 w-32 h-32 bg-gradient-to-bl from-violet-500/5 to-transparent rounded-bl-full pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity" />
                          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-violet-50 to-purple-50 dark:from-violet-950/30 dark:to-purple-950/30 border border-violet-200 dark:border-violet-900/50 flex items-center justify-center shrink-0 relative z-10">
                            <Link2 size={18} className="text-violet-600 dark:text-violet-500" />
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 mb-1.5">
                              <span className="text-xs font-mono bg-[var(--bg)] border border-[var(--border)] px-1.5 py-0.5 rounded text-[var(--text-primary)]">
                                {link.from_doc?.reference_number || link.from_doc?.doc_type || '—'}
                              </span>
                              <ChevronRight size={12} className="text-[var(--text-muted)]" />
                              <span className="text-xs font-mono bg-[var(--bg)] border border-[var(--border)] px-1.5 py-0.5 rounded text-[var(--text-primary)]">
                                {link.to_doc?.reference_number || link.to_doc?.doc_type || '—'}
                              </span>
                            </div>
                            <div className="flex items-center gap-3">
                              <span className="text-xs text-[var(--text-muted)] capitalize">{link.link_type?.replace(/_/g, ' ')}</span>
                              {confidence !== null && (
                                <span className={cn(
                                  'text-[10px] font-bold px-2 py-0.5 rounded-full',
                                  confidence < 50 ? 'bg-red-100 text-red-700 dark:bg-red-950/40 dark:text-red-400' :
                                  confidence < 70 ? 'bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-400' :
                                  'bg-emerald-100 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-400'
                                )}>
                                  {confidence}% confidence
                                </span>
                              )}
                            </div>
                          </div>
                          {link.from_doc?.matter_id && (
                            <a
                              href={`/matters/${link.from_doc.matter_id}`}
                              className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-medium bg-gradient-to-r from-violet-600 to-purple-600 text-white hover:opacity-90 transition-opacity shrink-0"
                            >
                              View Graph <ExternalLink size={11} />
                            </a>
                          )}
                        </div>
                      )
                    })
                  )}
                </SectionWrapper>
              )
            }

            if (activeSection === 'tasks') {
              return (
                <SectionWrapper meta={meta} count={openTasks.length}>
                  {openTasks.length === 0 ? (
                    <EmptyState text={meta.emptyText} />
                  ) : (
                    openTasks.map((task: any) => {
                      const isOverdue = task.action_item_due_date && new Date(task.action_item_due_date) < new Date()
                      return (
                        <div key={task.id} className="group relative flex items-start gap-4 p-5 rounded-xl border border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] hover:shadow-[var(--shadow-md)] transition-all duration-300 overflow-hidden">
                          <div className={`absolute top-0 right-0 w-32 h-32 bg-gradient-to-bl ${isOverdue ? 'from-red-500/5' : 'from-blue-500/5'} to-transparent rounded-bl-full pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity`} />
                          <div className={cn(
                            'w-10 h-10 rounded-xl flex items-center justify-center shrink-0 border relative z-10',
                            isOverdue 
                              ? 'bg-gradient-to-br from-red-50 to-rose-50 dark:from-red-950/30 dark:to-rose-950/30 border-red-200 dark:border-red-900/50' 
                              : 'bg-gradient-to-br from-blue-50 to-indigo-50 dark:from-blue-950/30 dark:to-indigo-950/30 border-blue-200 dark:border-blue-900/50'
                          )}>
                            <CheckSquare size={18} className={isOverdue ? 'text-red-600 dark:text-red-500' : 'text-blue-600 dark:text-blue-500'} />
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-medium text-[var(--text-primary)] line-clamp-2 mb-1">{task.content}</p>
                            <div className="flex items-center gap-3 text-xs text-[var(--text-muted)]">
                              {task.matters && (
                                <span className="flex items-center gap-1">
                                  <FolderOpen size={11} />
                                  {task.matters.title}
                                </span>
                              )}
                              {task.action_item_due_date && (
                                <span className={cn(
                                  'flex items-center gap-1 font-medium',
                                  isOverdue ? 'text-red-600 dark:text-red-400' : 'text-[var(--text-secondary)]'
                                )}>
                                  <Clock size={11} />
                                  {isOverdue ? 'Overdue' : formatDistanceToNow(new Date(task.action_item_due_date), { addSuffix: true })}
                                </span>
                              )}
                            </div>
                          </div>
                          {task.matters?.id && (
                            <a
                              href={`/notes`}
                              className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-medium border border-[var(--border)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] transition-colors shrink-0"
                            >
                              Open Note <ChevronRight size={12} />
                            </a>
                          )}
                        </div>
                      )
                    })
                  )}
                </SectionWrapper>
              )
            }

            if (activeSection === 'staged') {
              return (
                <SectionWrapper meta={meta} count={stagedDocs.length}>
                  {stagedDocs.length === 0 ? (
                    <EmptyState text={meta.emptyText} />
                  ) : (
                    stagedDocs.map((doc: any) => (
                      <div key={doc.id} className="group relative flex items-start gap-4 p-5 rounded-xl border border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] hover:shadow-[var(--shadow-md)] transition-all duration-300 overflow-hidden">
                        <div className="absolute top-0 right-0 w-32 h-32 bg-gradient-to-bl from-emerald-500/5 to-transparent rounded-bl-full pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity" />
                        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-emerald-50 to-teal-50 dark:from-emerald-950/30 dark:to-teal-950/30 border border-emerald-200 dark:border-emerald-900/50 flex items-center justify-center shrink-0 relative z-10">
                          <Inbox size={18} className="text-emerald-600 dark:text-emerald-500" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-[var(--text-primary)] truncate mb-1">
                            {doc.storage_path?.split('/').pop() || 'Document'}
                          </p>
                          {doc.suggestion_reason && (
                            <p className="text-xs text-[var(--text-muted)] line-clamp-1 mb-1">{doc.suggestion_reason}</p>
                          )}
                          <span className="text-[11px] text-[var(--text-muted)]">
                            {formatDistanceToNow(new Date(doc.created_at), { addSuffix: true })}
                          </span>
                        </div>
                        <a
                          href="/inbox"
                          className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-medium bg-gradient-to-r from-emerald-600 to-teal-600 text-white hover:opacity-90 transition-opacity shrink-0"
                        >
                          Assign <ChevronRight size={12} />
                        </a>
                      </div>
                    ))
                  )}
                </SectionWrapper>
              )
            }

            return null
          })()}
        </div>
      </div>
    </div>
  )
}

function SectionWrapper({ meta, count, children }: { meta: typeof SECTION_META[Section]; count: number; children: React.ReactNode }) {
  const Icon = meta.icon
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-3 pb-4 border-b border-[var(--border)]">
        <div className="w-10 h-10 rounded-xl flex items-center justify-center bg-[var(--surface)] border border-[var(--border-strong)] shrink-0 shadow-sm">
          <Icon size={20} className={meta.color} />
        </div>
        <div>
          <h2 className="text-sm font-bold text-[var(--text-primary)]">{meta.label}</h2>
          <p className="text-xs text-[var(--text-muted)]">{meta.desc}</p>
        </div>
        <span className="ml-auto text-xs font-bold bg-[var(--surface-hover)] border border-[var(--border)] px-2 py-0.5 rounded-full text-[var(--text-muted)]">
          {count} item{count !== 1 ? 's' : ''}
        </span>
      </div>
      <div className="flex flex-col gap-2">{children}</div>
    </div>
  )
}

function EmptyState({ text }: { text: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-16 gap-3">
      <div className="w-12 h-12 rounded-xl bg-emerald-100 dark:bg-emerald-950/40 flex items-center justify-center">
        <Check size={22} className="text-emerald-600 dark:text-emerald-400" />
      </div>
      <p className="text-sm font-medium text-[var(--text-secondary)]">{text}</p>
    </div>
  )
}
