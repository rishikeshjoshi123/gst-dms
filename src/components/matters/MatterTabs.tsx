'use client'

import { useState, useEffect, useRef } from 'react'
import { createClient } from '@/lib/supabase/client'
import { MatterTimelineTab } from './MatterTimelineTab'
import { FileText, Clock, FileKey, StickyNote, Info } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { CaseWikiTab } from './CaseWikiTab'
import { MatterNotesTab } from './MatterNotesTab'
import { MatterDetailsTab } from './MatterDetailsTab'
import Link from 'next/link'
import type { DocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'

export function MatterTabs({
  matter,
  proceedings,
  supporting,
  links,
  wikiSections,
  notes,
  users,
  inspectorMetadataByDocumentId
}: {
  matter: any,
  proceedings: any[],
  supporting: any[],
  links: any[],
  wikiSections: any[],
  notes: any[],
  users: any[],
  inspectorMetadataByDocumentId: Record<string, DocumentInspectorMetadata>
}) {
  const [activeTab, setActiveTab] = useState<'timeline' | 'files' | 'wiki' | 'notes' | 'details'>('timeline')

  // Local state for realtime updates
  const [localProceedings, setLocalProceedings] = useState(proceedings)
  const [localSupporting, setLocalSupporting] = useState(supporting)
  const [localLinks, setLocalLinks] = useState(links)
  const [localWikiSections, setLocalWikiSections] = useState(wikiSections)
  const [localNotes, setLocalNotes] = useState(notes)
  const matterDocumentIdsRef = useRef<Set<string>>(new Set())
  const matterLinkIdsRef = useRef<Set<string>>(new Set())
  const matterWikiSectionIdsRef = useRef<Set<string>>(new Set())
  const matterNoteIdsRef = useRef<Set<string>>(new Set())

  useEffect(() => { setLocalProceedings(proceedings) }, [proceedings])
  useEffect(() => { setLocalSupporting(supporting) }, [supporting])
  useEffect(() => { setLocalLinks(links) }, [links])
  useEffect(() => { setLocalWikiSections(wikiSections) }, [wikiSections])
  useEffect(() => { setLocalNotes(notes) }, [notes])

  useEffect(() => {
    matterDocumentIdsRef.current = new Set([
      ...localProceedings.map(document => document.id),
      ...localSupporting.map(document => document.id),
    ])
  }, [localProceedings, localSupporting])
  useEffect(() => { matterLinkIdsRef.current = new Set(localLinks.map(link => link.id)) }, [localLinks])
  useEffect(() => { matterWikiSectionIdsRef.current = new Set(localWikiSections.map(section => section.id)) }, [localWikiSections])
  useEffect(() => { matterNoteIdsRef.current = new Set(localNotes.map(note => note.id)) }, [localNotes])

  useEffect(() => {
    const supabase = createClient()
    const matterId = matter.id
    let timelineRefreshTimer: ReturnType<typeof setTimeout> | undefined
    let disposed = false

    const refreshTimeline = () => {
      if (timelineRefreshTimer) clearTimeout(timelineRefreshTimer)
      timelineRefreshTimer = setTimeout(async () => {
        const { getDocumentsByMatter } = await import('@/lib/actions/document')
        const { proceedings: p, supporting: s, links: l } = await getDocumentsByMatter(matterId)
        setLocalProceedings(p)
        setLocalSupporting(s)
        setLocalLinks(l || [])
      }, 200)
    }

    // Setup Realtime subscriptions
    const channel = supabase.channel(`matter_${matterId}_updates`)
      .on(
        'postgres_changes',
        // Supabase Realtime's UUID column filter can acknowledge a subscription
        // without delivering events in local deployments. Subscribe to the
        // RLS-scoped table and narrow events by their payload instead, so an
        // assignment appears immediately rather than only after a page reload.
        { event: '*', schema: 'public', table: 'documents' },
        (payload) => {
          const document = (payload.new ?? payload.old) as { id?: string, matter_id?: string }
          // DELETE payloads contain only the primary key unless the table uses
          // REPLICA IDENTITY FULL, so also match the ids we already render.
          if (document.matter_id === matterId || (document.id && matterDocumentIdsRef.current.has(document.id))) {
            refreshTimeline()
          }
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'document_links' },
        (payload) => {
          // Links do not store matter_id. Ignore unrelated organisation-wide
          // events by matching their endpoints to documents currently in this
          // matter; document events above cover newly inserted documents.
          const link = (payload.new ?? payload.old) as {
            id?: string
            from_doc_id?: string
            to_doc_id?: string | null
          }
          const endpointIds = [link?.from_doc_id, link?.to_doc_id].filter(Boolean)
          if (endpointIds.some(id => id && matterDocumentIdsRef.current.has(id)) ||
              (link.id && matterLinkIdsRef.current.has(link.id))) {
            refreshTimeline()
          }
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'wiki_sections' },
        async (payload) => {
          const section = (payload.new ?? payload.old) as { id?: string, matter_id?: string }
          if (section.matter_id === matterId || (section.id && matterWikiSectionIdsRef.current.has(section.id))) {
            const { getWikiSections } = await import('@/lib/actions/wiki')
            const w = await getWikiSections(matterId)
            setLocalWikiSections(w || [])
          }
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'case_notes' },
        async (payload) => {
          const note = (payload.new ?? payload.old) as { id?: string, matter_id?: string }
          if (note.matter_id === matterId || (note.id && matterNoteIdsRef.current.has(note.id))) {
            const { getNotes } = await import('@/lib/actions/notes')
            const n = await getNotes({ matterId })
            setLocalNotes(n || [])
          }
        }
      )
    // The server-rendered page can hydrate before the browser client has read
    // its auth cookie. Starting the channel anonymously makes RLS silently
    // suppress every row event, even though the channel reports SUBSCRIBED.
    // Set the session token first, then subscribe.
    void (async () => {
      const { data: { session } } = await supabase.auth.getSession()
      if (session?.access_token) await supabase.realtime.setAuth(session.access_token)
      if (disposed) return

      channel.subscribe((status, error) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          console.error('Matter realtime subscription unavailable', { matterId, status, error })
        }
      })
    })()

    return () => {
      disposed = true
      if (timelineRefreshTimer) clearTimeout(timelineRefreshTimer)
      supabase.removeChannel(channel)
    }
  }, [matter.id])


  return (
    <div className="flex flex-col flex-1 min-h-0 overflow-hidden mt-2">
      <div className="flex items-center gap-6 border-b border-[var(--border)] mb-6 px-2 shrink-0">
        <button
          onClick={() => setActiveTab('timeline')}
          className={`flex items-center gap-2 pb-3 px-1 border-b-2 transition-colors ${activeTab === 'timeline'
            ? 'border-[var(--primary)] text-[var(--text-primary)] font-medium'
            : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text-primary)]'
            }`}
        >
          <Clock size={16} />
          Timeline
          <Badge variant="muted" className="ml-1 px-1.5 py-0 text-[10px] h-4 border border-[var(--border)] bg-[var(--surface-hover)]">
            {localProceedings.length}
          </Badge>
        </button>

        <button
          onClick={() => setActiveTab('files')}
          className={`flex items-center gap-2 pb-3 px-1 border-b-2 transition-colors ${activeTab === 'files'
            ? 'border-[var(--primary)] text-[var(--text-primary)] font-medium'
            : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text-primary)]'
            }`}
        >
          <FileText size={16} />
          Files
          <Badge variant="muted" className="ml-1 px-1.5 py-0 text-[10px] h-4 border border-[var(--border)] bg-[var(--surface-hover)]">
            {localSupporting.length}
          </Badge>
        </button>

        <button
          onClick={() => setActiveTab('wiki')}
          className={`flex items-center gap-2 pb-3 px-1 border-b-2 transition-colors ${activeTab === 'wiki'
            ? 'border-[var(--primary)] text-[var(--text-primary)] font-medium'
            : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text-primary)]'
            }`}
        >
          <FileKey size={16} />
          CaseWiki
        </button>

        <button
          onClick={() => setActiveTab('notes')}
          className={`flex items-center gap-2 pb-3 px-1 border-b-2 transition-colors ${activeTab === 'notes'
            ? 'border-[var(--primary)] text-[var(--text-primary)] font-medium'
            : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text-primary)]'
            }`}
        >
          <StickyNote size={16} />
          Notes
          <Badge variant="muted" className="ml-1 px-1.5 py-0 text-[10px] h-4 border border-[var(--border)] bg-[var(--surface-hover)]">
            {localNotes.length}
          </Badge>
        </button>

        <button
          onClick={() => setActiveTab('details')}
          className={`flex items-center gap-2 pb-3 px-1 border-b-2 transition-colors ml-auto ${activeTab === 'details'
            ? 'border-[var(--primary)] text-[var(--text-primary)] font-medium'
            : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text-primary)]'
            }`}
        >
          <Info size={16} />
          Details
        </button>
      </div>

      <div className={`flex-1 min-h-0 ${activeTab === 'timeline' ? 'overflow-visible flex flex-col' : 'overflow-y-auto pr-1 custom-scrollbar pb-8'}`}>
        {activeTab === 'timeline' && (
          <MatterTimelineTab
            documents={[...localProceedings, ...localSupporting]}
            links={localLinks}
            notes={localNotes}
            inspectorMetadataByDocumentId={inspectorMetadataByDocumentId}
          />
        )}

        {activeTab === 'files' && (
          <div className="flex flex-col gap-4">
            {localSupporting.length === 0 ? (
              <div className="py-12 text-center text-[var(--text-muted)] border border-dashed border-[var(--border-strong)] rounded-lg">
                <p>No supporting files found in this matter.</p>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {localSupporting.map(doc => (
                  <Link href={`/matters/${doc.matter_id}/documents/${doc.id}`} key={doc.id} className="flex flex-col p-4 rounded-lg border border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] transition-colors">
                    <div className="flex items-start justify-between gap-4">
                      <div className="flex flex-col gap-1 min-w-0">
                        <span className="font-medium text-[var(--text-primary)] text-sm truncate" title={doc.storage_path.split('/').pop()}>
                          {doc.storage_path.split('/').pop()}
                        </span>
                        {doc.document_category && (
                          <span className="text-[10px] text-[var(--text-muted)] font-medium tracking-wider uppercase">
                            {doc.document_category.replace('_', ' ')}
                          </span>
                        )}
                      </div>
                    </div>
                  </Link>
                ))}
              </div>
            )}
          </div>
        )}

        {activeTab === 'wiki' && (
          <CaseWikiTab matterId={matter.id} initialSections={localWikiSections} />
        )}

        {activeTab === 'notes' && (
          <MatterNotesTab
            matterId={matter.id}
            initialNotes={localNotes}
            documents={[...localProceedings, ...localSupporting]}
            users={users}
          />
        )}

        {activeTab === 'details' && (
          <MatterDetailsTab matter={matter} />
        )}
      </div>
    </div>
  )
}
