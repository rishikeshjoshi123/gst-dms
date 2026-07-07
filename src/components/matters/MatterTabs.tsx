'use client'

import { useState } from 'react'
import { MatterTimelineTab } from './MatterTimelineTab'
import { FileText, Clock, FileKey, StickyNote } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { CaseWikiTab } from './CaseWikiTab'
import { MatterNotesTab } from './MatterNotesTab'
import Link from 'next/link'

export function MatterTabs({ 
  matterId,
  proceedings, 
  supporting, 
  links,
  wikiSections,
  notes,
  users
}: { 
  matterId: string,
  proceedings: any[], 
  supporting: any[], 
  links: any[],
  wikiSections: any[],
  notes: any[],
  users: any[]
}) {
  const [activeTab, setActiveTab] = useState<'timeline' | 'files' | 'wiki' | 'notes'>('timeline')

  return (
    <div className="flex flex-col flex-1 min-h-0 overflow-hidden mt-4">
      <div className="flex items-center gap-6 border-b border-[--border-subtle] mb-6 px-2 shrink-0">
        <button
          onClick={() => setActiveTab('timeline')}
          className={`flex items-center gap-2 pb-3 px-1 border-b-2 transition-colors ${
            activeTab === 'timeline'
              ? 'border-[--primary] text-[--text-primary] font-medium'
              : 'border-transparent text-[--text-muted] hover:text-[--text-primary]'
          }`}
        >
          <Clock size={16} />
          Timeline
          <Badge variant="muted" className="ml-1 px-1.5 py-0 text-[10px] h-4">
            {proceedings.length}
          </Badge>
        </button>

        <button
          onClick={() => setActiveTab('files')}
          className={`flex items-center gap-2 pb-3 px-1 border-b-2 transition-colors ${
            activeTab === 'files'
              ? 'border-[--primary] text-[--text-primary] font-medium'
              : 'border-transparent text-[--text-muted] hover:text-[--text-primary]'
          }`}
        >
          <FileText size={16} />
          Files
          <Badge variant="muted" className="ml-1 px-1.5 py-0 text-[10px] h-4">
            {supporting.length}
          </Badge>
        </button>

        <button
          onClick={() => setActiveTab('wiki')}
          className={`flex items-center gap-2 pb-3 px-1 border-b-2 transition-colors ${
            activeTab === 'wiki'
              ? 'border-[--primary] text-[--text-primary] font-medium'
              : 'border-transparent text-[--text-muted] hover:text-[--text-primary]'
          }`}
        >
          <FileKey size={16} />
          CaseWiki
        </button>

        <button
          onClick={() => setActiveTab('notes')}
          className={`flex items-center gap-2 pb-3 px-1 border-b-2 transition-colors ${
            activeTab === 'notes'
              ? 'border-[--primary] text-[--text-primary] font-medium'
              : 'border-transparent text-[--text-muted] hover:text-[--text-primary]'
          }`}
        >
          <StickyNote size={16} />
          Notes
          <Badge variant="muted" className="ml-1 px-1.5 py-0 text-[10px] h-4">
            {notes.length}
          </Badge>
        </button>
      </div>

      <div className={`flex-1 min-h-0 ${activeTab === 'timeline' ? 'overflow-visible flex flex-col' : 'overflow-y-auto pr-1 custom-scrollbar pb-8'}`}>
        {activeTab === 'timeline' && (
          <MatterTimelineTab documents={proceedings} links={links} notes={notes} />
        )}

        {activeTab === 'files' && (
          <div className="flex flex-col gap-4">
            {supporting.length === 0 ? (
              <div className="py-12 text-center text-[--text-muted] border border-dashed border-[--border-strong] rounded-lg">
                <p>No supporting files found in this matter.</p>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {supporting.map(doc => (
                  <Link href={`/matters/${doc.matter_id}/documents/${doc.id}`} key={doc.id} className="flex flex-col p-4 rounded-lg border border-[--border-subtle] bg-[--bg-surface] hover:border-[--border-default] transition-colors">
                    <div className="flex items-start justify-between gap-4">
                      <div className="flex flex-col gap-1 min-w-0">
                        <span className="font-medium text-[--text-primary] text-sm truncate" title={doc.storage_path.split('/').pop()}>
                          {doc.storage_path.split('/').pop()}
                        </span>
                        {doc.document_category && (
                          <span className="text-[10px] text-[--text-muted] font-medium tracking-wider uppercase">
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
          <CaseWikiTab matterId={matterId} initialSections={wikiSections} />
        )}

        {activeTab === 'notes' && (
          <MatterNotesTab
            matterId={matterId}
            initialNotes={notes}
            documents={[...proceedings, ...supporting]}
            users={users}
          />
        )}
      </div>
    </div>
  )
}
