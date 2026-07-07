'use client'

import { useState } from 'react'
import { TimelineGraph } from './TimelineGraph'
import { TimelineDocumentDetail } from './TimelineDocumentDetail'

export function MatterTimelineTab({ documents, links, notes = [] }: { documents: any[], links: any[], notes?: any[] }) {
  const [selectedDocId, setSelectedDocId] = useState<string | null>(null)

  const selectedDoc = documents.find(d => d.id === selectedDocId) || null

  return (
    <div className="flex flex-col lg:flex-row gap-6 w-full h-full overflow-hidden min-h-0">
      <div className={`transition-all duration-300 ease-in-out h-full overflow-y-auto pr-1 custom-scrollbar ${selectedDoc ? 'lg:w-[45%] w-full shrink-0' : 'w-full'}`}>
        <TimelineGraph 
          documents={documents} 
          links={links} 
          selectedDocId={selectedDocId}
          onSelectDoc={setSelectedDocId}
        />
      </div>
      
      {selectedDoc && (
        <div className="w-full lg:w-[55%] h-full overflow-y-auto pr-1 custom-scrollbar shrink-0">
          <TimelineDocumentDetail 
            doc={selectedDoc} 
            notes={notes}
            onClose={() => setSelectedDocId(null)}
          />
        </div>
      )}
    </div>
  )
}
