'use client'

import { useState } from 'react'
import { TimelineGraph } from './TimelineGraph'
import { TimelineDocumentDetail } from './TimelineDocumentDetail'

export function MatterTimelineTab({ documents, links, notes = [] }: { documents: any[], links: any[], notes?: any[] }) {
  const [selectedDocId, setSelectedDocId] = useState<string | null>(null)

  const selectedDoc = documents.find(d => d.id === selectedDocId) || null

  return (
    <div className="relative w-full h-full overflow-hidden rounded-lg">
      <div className="w-full h-full">
        <TimelineGraph 
          documents={documents} 
          links={links} 
          selectedDocId={selectedDocId}
          onSelectDoc={setSelectedDocId}
        />
      </div>
      
      {selectedDoc && (
        <div className="absolute top-0 right-0 h-full w-[420px] max-w-[90%] z-50 animate-in slide-in-from-right-8 duration-300 p-4 drop-shadow-2xl">
          <TimelineDocumentDetail 

            doc={selectedDoc} 
            allDocuments={documents}
            links={links}
            notes={notes}
            onClose={() => setSelectedDocId(null)}
          />
        </div>
      )}
    </div>
  )
}
