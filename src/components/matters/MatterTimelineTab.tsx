'use client'

import { useState } from 'react'
import { TimelineGraph } from './TimelineGraph'
import { TimelineDocumentDetail } from './TimelineDocumentDetail'
import { TimelineListFallback, type TimelineDocument, type TimelineLink } from './TimelineListFallback'
import { ChevronLeft } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { DocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'

export function MatterTimelineTab({ documents, links, notes = [], inspectorMetadataByDocumentId, readOnly = false }: {
  documents: TimelineDocument[]
  links: TimelineLink[]
  notes?: Record<string, unknown>[]
  inspectorMetadataByDocumentId: Record<string, DocumentInspectorMetadata>
  readOnly?: boolean
}) {
  const [selectedDocId, setSelectedDocId] = useState<string | null>(null)

  const selectedDoc = documents.find(d => d.id === selectedDocId) || null

  return (
    <div className="relative w-full h-full overflow-hidden rounded-[var(--radius-md)] flex flex-col md:block">
      {/* Mobile view (list) */}
      <div className={cn("w-full h-full block md:hidden", selectedDocId ? "hidden" : "block")}>
        <TimelineListFallback
          documents={documents}
          links={links}
          selectedDocId={selectedDocId}
          onSelectDoc={setSelectedDocId}
          inspectorMetadataByDocumentId={inspectorMetadataByDocumentId}
        />
      </div>

      {/* Desktop view (graph) */}
      <div className="w-full h-full hidden md:block">
        <TimelineGraph 
          documents={documents} 
          links={links} 
          selectedDocId={selectedDocId}
          onSelectDoc={setSelectedDocId}
          inspectorMetadataByDocumentId={inspectorMetadataByDocumentId}
          readOnly={readOnly}
        />
      </div>
      
      {selectedDoc && (
        <div className={cn(
          "absolute top-0 right-0 h-full z-50 bg-[var(--surface)] transition-all duration-300",
          "w-full md:w-[420px] md:max-w-[90%] md:drop-shadow-2xl md:border-l border-[var(--border)]",
          "animate-in slide-in-from-right-8"
        )}>
          {/* Mobile back button */}
          <div className="md:hidden flex items-center p-2 border-b border-[var(--border)] bg-[var(--bg)]">
            <button
              type="button"
              onClick={() => setSelectedDocId(null)}
              className="flex items-center gap-1 text-[13px] font-medium text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-2 py-1.5 rounded-[var(--radius-sm)] hover:bg-[var(--surface-hover)] transition-colors"
            >
              <ChevronLeft size={16} />
              Back to Timeline
            </button>
          </div>
          <div className="h-[calc(100%-48px)] md:h-full p-0 md:p-4 overflow-y-auto">
            <TimelineDocumentDetail
              doc={selectedDoc}
              allDocuments={documents}
              links={links}
              notes={notes}
              effectiveMetadata={inspectorMetadataByDocumentId[selectedDoc.id]}
              inspectorMetadataByDocumentId={inspectorMetadataByDocumentId}
              onClose={() => setSelectedDocId(null)}
              readOnly={readOnly}
            />
          </div>
        </div>
      )}
    </div>
  )
}
