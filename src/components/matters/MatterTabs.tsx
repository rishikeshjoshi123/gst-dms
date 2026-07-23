'use client'

import { useState } from 'react'
import { MatterTimelineTab } from './MatterTimelineTab'
import { FileText, Clock, FileKey, StickyNote, Info } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { CaseWikiTab } from './CaseWikiTab'
import { MatterNotesTab } from './MatterNotesTab'
import { MatterDetailsTab } from './MatterDetailsTab'
import Link from 'next/link'

export function MatterTabs({
  matter,
  proceedings,
  supporting,
  links,
  wikiSections,
  notes,
  users
}: {
  matter: any,
  proceedings: any[],
  supporting: any[],
  links: any[],
  wikiSections: any[],
  notes: any[],
  users: any[]
}) {
  const [activeTab, setActiveTab] = useState<'timeline' | 'files' | 'wiki' | 'notes' | 'details'>('timeline')

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
            {proceedings.length}
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
            {supporting.length}
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
            {notes.length}
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
          <MatterTimelineTab documents={[...proceedings, ...supporting]} links={links} notes={notes} />
        )}

        {activeTab === 'files' && (
          <div className="flex flex-col gap-4">
            {supporting.length === 0 ? (
              <div className="py-12 text-center text-[var(--text-muted)] border border-dashed border-[var(--border-strong)] rounded-lg">
                <p>No supporting files found in this matter.</p>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {supporting.map(doc => (
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
          <CaseWikiTab matterId={matter.id} initialSections={wikiSections} />
        )}

        {activeTab === 'notes' && (
          <MatterNotesTab
            matterId={matter.id}
            initialNotes={notes}
            documents={[...proceedings, ...supporting]}
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
