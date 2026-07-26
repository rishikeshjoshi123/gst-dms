'use client'

import { useState, useTransition } from 'react'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { toast } from 'sonner'
import { dismissReviewFlag } from '@/lib/actions/document'
import { useRouter } from 'next/navigation'
import {
  AlertTriangle, Link2, CheckSquare, Inbox,
  FileText, FolderOpen, ExternalLink, Check, X,
  ChevronRight, ChevronLeft
} from 'lucide-react'
import { Badge } from '@/components/ui/badge'

type Section = 'docs' | 'links' | 'tasks' | 'staged'

const ITEMS_PER_PAGE = 10

const SECTION_META = {
  docs: {
    icon: AlertTriangle,
    label: 'Documents Needing Review',
    emptyText: 'No documents need manual review',
  },
  links: {
    icon: Link2,
    label: 'Low-Confidence Links',
    emptyText: 'No pending link suggestions',
  },
  tasks: {
    icon: CheckSquare,
    label: 'Open Action Items',
    emptyText: 'No open action items',
  },
  staged: {
    icon: Inbox,
    label: 'Staged Documents',
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
  const [pageMap, setPageMap] = useState<Record<Section, number>>({
    docs: 1,
    links: 1,
    tasks: 1,
    staged: 1,
  })

  // Filter low-confidence links to strictly require BOTH from_doc AND to_doc to exist
  const validPendingLinks = (pendingLinks || []).filter(
    (l: any) => l.from_doc && l.to_doc && l.from_doc.id && l.to_doc.id
  )

  const visibleDocs = needsReviewDocs.filter(d => !dismissedDocs.has(d.id))

  const sections: { key: Section; count: number }[] = [
    { key: 'docs', count: visibleDocs.length },
    { key: 'links', count: validPendingLinks.length },
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

  // Get current section items & pagination
  const getCurrentItems = () => {
    switch (activeSection) {
      case 'docs': return visibleDocs
      case 'links': return validPendingLinks
      case 'tasks': return openTasks
      case 'staged': return stagedDocs
    }
  }

  const items = getCurrentItems()
  const currentPage = pageMap[activeSection] || 1
  const totalPages = Math.max(1, Math.ceil(items.length / ITEMS_PER_PAGE))
  const paginatedItems = items.slice((currentPage - 1) * ITEMS_PER_PAGE, currentPage * ITEMS_PER_PAGE)

  const handlePageChange = (newPage: number) => {
    setPageMap(prev => ({ ...prev, [activeSection]: newPage }))
  }

  return (
    <div className="flex flex-col flex-1 min-h-0 overflow-hidden mt-2 animate-fade-in">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Pending Review' }]} />

      {/* Tabs directly below breadcrumbs (identical to MatterTabs layout) */}
      <div className="flex items-center gap-6 border-b border-[var(--border)] mb-6 px-2 shrink-0 overflow-x-auto custom-scrollbar">
        {sections.map(({ key, count }) => {
          const meta = SECTION_META[key]
          const Icon = meta.icon
          const isActive = activeSection === key
          return (
            <button
              key={key}
              onClick={() => setActiveSection(key)}
              className={`flex items-center gap-2 pb-3 px-1 border-b-2 transition-colors shrink-0 text-sm ${
                isActive
                  ? 'border-[var(--primary)] text-[var(--text-primary)] font-medium'
                  : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text-primary)]'
              }`}
            >
              <Icon size={16} />
              <span>{meta.label}</span>
              <Badge
                variant="muted"
                className="ml-1 px-1.5 py-0 text-[10px] h-4 border border-[var(--border)] bg-[var(--surface-hover)] text-[var(--text-secondary)] font-medium"
              >
                {count}
              </Badge>
            </button>
          )
        })}
      </div>

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col min-h-0 overflow-hidden">
        <div className="flex-1 overflow-y-auto custom-scrollbar pr-2 space-y-3">
          {paginatedItems.length === 0 ? (
            <EmptyState text={SECTION_META[activeSection].emptyText} />
          ) : (
            paginatedItems.map((item: any) => {
              if (activeSection === 'docs') {
                const doc = item
                return (
                  <div key={doc.id} className="group relative flex items-center justify-between gap-4 p-3.5 px-4 rounded-lg border border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] hover:shadow-xs transition-all">
                    <div className="flex items-center gap-3 min-w-0 flex-1">
                      <FileText size={16} className="text-amber-500 shrink-0" />
                      <div className="flex flex-col min-w-0 flex-1">
                        <div className="flex items-center gap-2">
                          <span className="font-medium text-xs text-[var(--text-primary)] truncate">
                            {doc.doc_type || doc.storage_path?.split('/').pop() || 'Unknown document'}
                          </span>
                          {doc.reference_number && (
                            <span className="text-[10px] font-mono bg-[var(--bg)] border border-[var(--border)] px-1.5 py-0.2 rounded text-[var(--text-muted)] shrink-0">
                              {doc.reference_number}
                            </span>
                          )}
                        </div>
                        {doc.review_reason && (
                          <span className="text-[11px] text-[var(--text-muted)] truncate">{doc.review_reason}</span>
                        )}
                        {doc.matters && (
                          <span className="text-[11px] text-[var(--text-secondary)] flex items-center gap-1 mt-0.5">
                            <FolderOpen size={11} className="text-[var(--text-muted)]" />
                            {doc.matters.clients?.name} · {doc.matters.title}
                          </span>
                        )}
                      </div>
                    </div>

                    <div className="flex items-center gap-2 shrink-0">
                      <button
                        onClick={() => handleDismissDoc(doc.id)}
                        disabled={isPending}
                        className="flex items-center gap-1 px-2.5 py-1 rounded text-xs font-medium text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--surface-hover)] border border-[var(--border)] transition-colors"
                      >
                        <X size={12} />
                        Dismiss
                      </button>
                      {doc.matters?.id && (
                        <a
                          href={`/matters/${doc.matters.id}?from=review`}
                          className="flex items-center gap-1 px-2.5 py-1 rounded text-xs font-medium bg-[var(--primary)] text-white hover:opacity-90 transition-opacity"
                        >
                          View <ChevronRight size={12} />
                        </a>
                      )}
                    </div>
                  </div>
                )
              }

              if (activeSection === 'links') {
                const link = item
                const confidence = link.confidence ? Math.round(link.confidence * 100) : null
                return (
                  <div key={link.id} className="group relative flex items-center justify-between gap-4 p-3.5 px-4 rounded-lg border border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] hover:shadow-xs transition-all">
                    <div className="flex items-center gap-3 min-w-0 flex-1">
                      <Link2 size={16} className="text-violet-500 shrink-0" />
                      <div className="flex items-center gap-2 min-w-0 flex-1">
                        <span className="font-mono text-xs text-[var(--text-primary)] font-semibold truncate bg-[var(--bg)] border border-[var(--border)] px-2 py-0.5 rounded">
                          {link.from_doc?.doc_type || 'DOC'} ({link.from_doc?.reference_number || 'Ref'})
                        </span>
                        <ChevronRight size={13} className="text-[var(--text-muted)] shrink-0" />
                        <span className="font-mono text-xs text-[var(--text-primary)] font-semibold truncate bg-[var(--bg)] border border-[var(--border)] px-2 py-0.5 rounded">
                          {link.to_doc?.doc_type || 'DOC'} ({link.to_doc?.reference_number || 'Ref'})
                        </span>
                        {confidence !== null && (
                          <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ml-2 shrink-0 ${
                            confidence < 50 ? 'bg-red-500/10 text-red-600 border border-red-500/20' :
                            confidence < 70 ? 'bg-amber-500/10 text-amber-600 border border-amber-500/20' :
                            'bg-emerald-500/10 text-emerald-600 border border-emerald-500/20'
                          }`}>
                            {confidence}% confidence
                          </span>
                        )}
                      </div>
                    </div>

                    {link.from_doc?.matter_id && (
                      <a
                        href={`/matters/${link.from_doc.matter_id}?from=review`}
                        className="flex items-center gap-1 px-3 py-1 rounded text-xs font-medium bg-[var(--primary)] text-white hover:opacity-90 transition-opacity shrink-0"
                      >
                        View Graph <ExternalLink size={11} />
                      </a>
                    )}
                  </div>
                )
              }

              if (activeSection === 'tasks') {
                const task = item
                return (
                  <div key={task.id} className="group relative flex items-center justify-between gap-4 p-3.5 px-4 rounded-lg border border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] hover:shadow-xs transition-all">
                    <div className="flex items-center gap-3 min-w-0 flex-1">
                      <CheckSquare size={16} className="text-blue-500 shrink-0" />
                      <div className="flex flex-col min-w-0 flex-1">
                        <span className="text-xs text-[var(--text-primary)] line-clamp-1 font-medium">{task.content}</span>
                        {task.matters && (
                          <span className="text-[11px] text-[var(--text-muted)] flex items-center gap-1 mt-0.5">
                            <FolderOpen size={11} />
                            {task.matters.title} ({task.matters.matter_code || 'no code'})
                          </span>
                        )}
                      </div>
                    </div>

                    {task.matters?.id && (
                      <a
                        href={`/matters/${task.matters.id}?from=review`}
                        className="flex items-center gap-1 px-3 py-1 rounded text-xs font-medium bg-[var(--primary)] text-white hover:opacity-90 transition-opacity shrink-0"
                      >
                        View Matter <ChevronRight size={12} />
                      </a>
                    )}
                  </div>
                )
              }

              if (activeSection === 'staged') {
                const staged = item
                return (
                  <div key={staged.id} className="group relative flex items-center justify-between gap-4 p-3.5 px-4 rounded-lg border border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] hover:shadow-xs transition-all">
                    <div className="flex items-center gap-3 min-w-0 flex-1">
                      <Inbox size={16} className="text-emerald-500 shrink-0" />
                      <div className="flex flex-col min-w-0 flex-1">
                        <span className="text-xs text-[var(--text-primary)] font-medium truncate">
                          {staged.storage_path?.split('/').pop() || 'Staged File'}
                        </span>
                        <span className="text-[11px] text-[var(--text-muted)]">
                          Uploaded {new Date(staged.created_at).toLocaleDateString()}
                        </span>
                      </div>
                    </div>

                    <a
                      href="/inbox"
                      className="flex items-center gap-1 px-3 py-1 rounded text-xs font-medium bg-[var(--primary)] text-white hover:opacity-90 transition-opacity shrink-0"
                    >
                      Assign <ChevronRight size={12} />
                    </a>
                  </div>
                )
              }

              return null
            })
          )}
        </div>

        {/* Pagination Footer */}
        {items.length > ITEMS_PER_PAGE && (
          <div className="flex items-center justify-between pt-3 pb-1 px-1 border-t border-[var(--border)] shrink-0 text-xs text-[var(--text-muted)]">
            <span>
              Showing {((currentPage - 1) * ITEMS_PER_PAGE) + 1} to {Math.min(currentPage * ITEMS_PER_PAGE, items.length)} of {items.length} items
            </span>

            <div className="flex items-center gap-2">
              <button
                onClick={() => handlePageChange(currentPage - 1)}
                disabled={currentPage === 1}
                className="p-1 px-2 rounded border border-[var(--border)] bg-[var(--surface)] hover:bg-[var(--surface-hover)] text-[var(--text-primary)] disabled:opacity-40 disabled:cursor-not-allowed flex items-center gap-1"
              >
                <ChevronLeft size={14} /> Prev
              </button>
              <span className="font-semibold text-[var(--text-primary)]">
                Page {currentPage} of {totalPages}
              </span>
              <button
                onClick={() => handlePageChange(currentPage + 1)}
                disabled={currentPage === totalPages}
                className="p-1 px-2 rounded border border-[var(--border)] bg-[var(--surface)] hover:bg-[var(--surface-hover)] text-[var(--text-primary)] disabled:opacity-40 disabled:cursor-not-allowed flex items-center gap-1"
              >
                Next <ChevronRight size={14} />
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function EmptyState({ text }: { text: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-16 gap-3 rounded-lg border border-[var(--border)] bg-[var(--surface)]">
      <div className="w-10 h-10 rounded-full bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center">
        <Check size={18} className="text-emerald-500" />
      </div>
      <p className="text-xs font-medium text-[var(--text-secondary)]">{text}</p>
    </div>
  )
}
