'use client'

import { useState, useEffect, useTransition } from 'react'
import { searchAll, SearchResultItem } from '@/lib/actions/search'
import { NeedsAttentionPanel } from './NeedsAttentionPanel'
import { ArrowUpRight, FileText, Search, Users, FolderOpen, Loader2, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import Link from 'next/link'

import { useBreadcrumbs } from '@/components/nav/BreadcrumbContext'

interface DashboardContentProps {
  firstName: string
  greeting: string
  orgName: string
  stats: {
    clients: number
    matters: number
    documents: number
  }
  needsReviewDocs: any[]
  statCards: Array<{
    label: string
    value: number
    href: string
  }>
}

export function DashboardContent({
  firstName,
  greeting,
  orgName,
  stats,
  needsReviewDocs,
  statCards,
}: DashboardContentProps) {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<SearchResultItem[]>([])
  const [isSearching, setIsSearching] = useState(false)
  const [isPending, startTransition] = useTransition()
  
  const { setBreadcrumbs } = useBreadcrumbs()

  useEffect(() => {
    setBreadcrumbs([])
  }, [setBreadcrumbs])

  // Real-time search debouncing
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
          const res = await searchAll(query)
          setResults(res)
        } catch (e) {
          console.error(e)
        }
      })
    }, 250) // 250ms debounce delay

    return () => clearTimeout(delayDebounce)
  }, [query])

  const clients = results.filter(r => r.type === 'client')
  const matters = results.filter(r => r.type === 'matter')
  const documents = results.filter(r => r.type === 'document')

  const showResults = query.trim().length >= 2

  return (
    <div className="flex flex-col flex-1 overflow-y-auto pr-1 custom-scrollbar">
      {/* Page header */}
      <div className="mb-6 animate-fade-in flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <h1 className="text-page-title text-[var(--text-primary)]">
            {greeting}, {firstName} 👋
          </h1>
          <p className="mt-1 text-body text-[var(--text-muted)]">
            Welcome to <span className="text-[var(--text-secondary)] font-semibold">{orgName}</span> workspace
          </p>
        </div>

        {/* Big Search Box */}
        <div className="relative w-full md:max-w-md">
          <Search size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-[var(--text-muted)] pointer-events-none" />
          <input
            type="text"
            placeholder="Search clients, matters, documents..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="w-full h-10 pl-10 pr-10 rounded-md text-[14px] bg-white text-[var(--text-primary)] placeholder:text-[var(--text-muted)] border border-[var(--border-strong)] focus:border-[var(--accent)] focus:ring-2 focus:ring-[var(--accent-ring)] outline-none transition-all duration-[var(--duration-fast)] shadow-[var(--shadow-sm)]"
          />
          {query && (
            <button
              onClick={() => setQuery('')}
              className="absolute right-3 top-1/2 -translate-y-1/2 p-1 text-[var(--text-muted)] hover:text-[var(--text-primary)] rounded-full hover:bg-[var(--bg-overlay)] transition-colors"
            >
              <X size={14} />
            </button>
          )}
        </div>
      </div>

      {/* Render search results or the default dashboard */}
      {showResults ? (
        <div className="mt-4 animate-fade-in">
          {/* Loading State */}
          {(isPending || (query.trim().length >= 2 && results.length === 0 && isSearching && isPending)) ? (
            <div className="flex flex-col items-center justify-center py-20 text-[var(--text-muted)] gap-3">
              <Loader2 size={24} className="animate-spin text-[var(--accent)]" />
              <p className="text-[14px]">Searching...</p>
            </div>
          ) : results.length === 0 ? (
            /* Empty State */
            <div className="rounded-md bg-white border border-[var(--border-default)] p-12 text-center shadow-[var(--shadow-sm)]">
              <p className="text-[14px] text-[var(--text-muted)]">
                No results found for &ldquo;<span className="text-[var(--text-primary)] font-semibold">{query}</span>&rdquo;
              </p>
              <p className="text-[12px] text-[var(--text-muted)] mt-1.5 uppercase tracking-wider">
                Try searching for a client name, matter title, or reference number
              </p>
            </div>
          ) : (
            /* Results Layout */
            <div className="flex flex-col gap-6">
              <div className="flex items-center justify-between border-b border-[var(--border-default)] pb-3">
                <h2 className="text-[16px] font-semibold text-[var(--text-primary)]">
                  Search Results for &ldquo;{query}&rdquo;
                </h2>
                <span className="text-xs text-[var(--text-muted)] uppercase tracking-wider font-medium">
                  {results.length} Match{results.length !== 1 && 'es'}
                </span>
              </div>

              {/* Clients Group */}
              {clients.length > 0 && (
                <div>
                  <h3 className="text-[12px] font-semibold text-[var(--text-muted)] uppercase tracking-wide mb-2.5">
                    Clients ({clients.length})
                  </h3>
                  <div className="flex flex-col gap-2.5">
                    {clients.map(item => (
                      <Link
                        key={item.id}
                        href={item.href}
                        className="group flex items-center justify-between p-3 rounded-md bg-white border border-[var(--border-default)] hover:shadow-[var(--shadow-sm)] transition-all duration-[var(--duration-fast)]"
                      >
                        <div className="flex items-center gap-3">
                          <div className="w-8 h-8 rounded-full bg-blue-50 flex items-center justify-center text-[var(--accent)] shrink-0">
                            <Users size={16} />
                          </div>
                          <div>
                            <p className="text-[14px] font-medium text-[var(--text-primary)]">{item.title}</p>
                            <p className="text-[12px] text-[var(--text-muted)]">{item.subtitle}</p>
                          </div>
                        </div>
                        <ArrowUpRight size={16} className="text-[var(--text-disabled)] group-hover:text-[var(--text-muted)] group-hover:translate-x-0.5 transition-all" />
                      </Link>
                    ))}
                  </div>
                </div>
              )}

              {/* Matters Group */}
              {matters.length > 0 && (
                <div>
                  <h3 className="text-[12px] font-semibold text-[var(--text-muted)] uppercase tracking-wide mb-2.5">
                    Matters ({matters.length})
                  </h3>
                  <div className="flex flex-col gap-2.5">
                    {matters.map(item => (
                      <Link
                        key={item.id}
                        href={item.href}
                        className="group flex items-center justify-between p-3 rounded-md bg-white border border-[var(--border-default)] hover:shadow-[var(--shadow-sm)] transition-all duration-[var(--duration-fast)]"
                      >
                        <div className="flex items-center gap-3">
                          <div className="w-8 h-8 rounded-full bg-amber-50 flex items-center justify-center text-amber-600 shrink-0">
                            <FolderOpen size={16} />
                          </div>
                          <div>
                            <p className="text-[14px] font-medium text-[var(--text-primary)]">{item.title}</p>
                            <p className="text-[12px] text-[var(--text-muted)]">{item.subtitle}</p>
                          </div>
                        </div>
                        <ArrowUpRight size={16} className="text-[var(--text-disabled)] group-hover:text-[var(--text-muted)] group-hover:translate-x-0.5 transition-all" />
                      </Link>
                    ))}
                  </div>
                </div>
              )}

              {/* Documents Group */}
              {documents.length > 0 && (
                <div>
                  <h3 className="text-[12px] font-semibold text-[var(--text-muted)] uppercase tracking-wide mb-2.5">
                    Documents ({documents.length})
                  </h3>
                  <div className="flex flex-col gap-2.5">
                    {documents.map(item => (
                      <Link
                        key={item.id}
                        href={item.href}
                        className="group flex items-center justify-between p-3 rounded-md bg-white border border-[var(--border-default)] hover:shadow-[var(--shadow-sm)] transition-all duration-[var(--duration-fast)]"
                      >
                        <div className="flex items-center gap-3">
                          <div className="w-8 h-8 rounded-full bg-slate-50 flex items-center justify-center text-slate-600 shrink-0">
                            <FileText size={16} />
                          </div>
                          <div>
                            <p className="text-[14px] font-medium text-[var(--text-primary)]">{item.title}</p>
                            <p className="text-[12px] text-[var(--text-muted)]">{item.subtitle}</p>
                          </div>
                        </div>
                        <ArrowUpRight size={16} className="text-[var(--text-disabled)] group-hover:text-[var(--text-muted)] group-hover:translate-x-0.5 transition-all" />
                      </Link>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      ) : (
        /* Default Dashboard view */
        <div className="animate-fade-in">
          {/* Stat cards */}
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4 mb-8 mt-2">
            {statCards.map(({ label, value, href }) => (
              <a
                key={label}
                href={href}
                className={cn(
                  "group flex flex-col p-5 rounded-md bg-white border border-[var(--border-default)] hover:border-[var(--border-strong)] shadow-[var(--shadow-sm)] transition-all duration-[var(--duration-base)] relative overflow-hidden",
                  label === 'Pending Review' && "border-l-[2px] border-l-[var(--sidebar-accent)]"
                )}
              >
                <div className="flex items-center justify-between mb-3">
                  <span className="text-[12px] font-medium uppercase tracking-wide text-[var(--text-secondary)]">{label}</span>
                  <ArrowUpRight size={16} className="text-[var(--text-disabled)] group-hover:text-[var(--text-muted)] transition-colors" />
                </div>
                <div>
                  <p className="text-[32px] font-bold text-[var(--text-primary)] leading-none">{value}</p>
                </div>
              </a>
            ))}
          </div>

          {/* Needs Attention Panel */}
          <NeedsAttentionPanel documents={needsReviewDocs} />

          {/* Getting started panel */}
          {stats.clients === 0 && (
            <div className="rounded-md bg-white border border-[var(--border-default)] p-8 text-center shadow-[var(--shadow-sm)]">
              <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-[var(--bg-base)]">
                <FileText size={24} className="text-[var(--text-muted)]" />
              </div>
              <h2 className="text-[18px] font-semibold text-[var(--text-primary)]">Welcome to GST DMS</h2>
              <p className="mt-2 text-[14px] text-[var(--text-muted)] max-w-sm mx-auto leading-relaxed">
                Your workspace is ready, but it looks a bit quiet in here. Let's start by adding your first client so we can begin tracking their matters.
              </p>
              <div className="mt-6 flex justify-center gap-3">
                <a
                  href="/clients"
                  className="inline-flex items-center gap-2 px-5 py-2.5 rounded-md bg-[var(--accent)] text-white text-sm font-medium hover:bg-[var(--accent-hover)] transition-colors"
                >
                  Add your first client
                  <ArrowUpRight size={14} />
                </a>
              </div>
            </div>
          )}

          {stats.clients > 0 && needsReviewDocs.length === 0 && (
            <div className="rounded-md bg-white border border-[var(--border-default)] p-6 shadow-[var(--shadow-sm)]">
              <h2 className="text-[14px] font-semibold text-[var(--text-primary)] mb-4">Recent Activity</h2>
              <p className="text-[14px] text-[var(--text-muted)]">
                Activity feed coming in a later phase.
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
