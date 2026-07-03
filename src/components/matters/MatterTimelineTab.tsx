'use client'

import { useState } from 'react'
import { TimelineGraph } from './TimelineGraph'
import { TimelineDocumentDetail } from './TimelineDocumentDetail'

export function MatterTimelineTab({ documents, links }: { documents: any[], links: any[] }) {
  const [selectedDocId, setSelectedDocId] = useState<string | null>(null)

  const selectedDoc = documents.find(d => d.id === selectedDocId) || null

  return (
    <div className="flex flex-col lg:flex-row gap-6 items-start">
      <div className={`transition-all duration-300 ease-in-out ${selectedDoc ? 'lg:w-[40%]' : 'w-full'}`}>
        <TimelineGraph 
          documents={documents} 
          links={links} 
          selectedDocId={selectedDocId}
          onSelectDoc={setSelectedDocId}
        />
      </div>
      
      {selectedDoc && (
        <div className="w-full lg:w-[60%] sticky top-8">
          <TimelineDocumentDetail 
            doc={selectedDoc} 
            onClose={() => setSelectedDocId(null)}
          />
        </div>
      )}
    </div>
  )
}
