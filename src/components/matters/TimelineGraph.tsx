'use client'

import { useState, useMemo } from 'react'
import { AlertCircle, Clock, Link as LinkIcon, FileText } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'

export function TimelineGraph({ 
  documents, 
  links,
  selectedDocId,
  onSelectDoc 
}: { 
  documents: any[], 
  links: any[],
  selectedDocId?: string | null,
  onSelectDoc?: (id: string) => void
}) {
  const [compact, setCompact] = useState(false)

  // 1. Identify roots (docs with no outgoing links to other docs)
  // An outgoing link means from_doc_id = currentDoc.id
  const outgoingLinksByDoc = useMemo(() => {
    const map = new Map<string, any[]>()
    links.forEach(l => {
      if (!map.has(l.from_doc_id)) map.set(l.from_doc_id, [])
      map.get(l.from_doc_id)!.push(l)
    })
    return map
  }, [links])

  const incomingLinksByDoc = useMemo(() => {
    const map = new Map<string, any[]>()
    links.forEach(l => {
      // Pending links have no to_doc_id
      if (l.to_doc_id) {
        if (!map.has(l.to_doc_id)) map.set(l.to_doc_id, [])
        map.get(l.to_doc_id)!.push(l)
      }
    })
    return map
  }, [links])

  const roots = useMemo(() => {
    // A root is a document that doesn't "respond" to anything else in this matter.
    // Meaning it has NO outgoing links to another document.
    return documents.filter(d => !outgoingLinksByDoc.has(d.id) || outgoingLinksByDoc.get(d.id)!.length === 0)
  }, [documents, outgoingLinksByDoc])

  const unlinked = useMemo(() => {
    // Documents that have no incoming AND no outgoing links
    return documents.filter(d => 
      (!outgoingLinksByDoc.has(d.id) || outgoingLinksByDoc.get(d.id)!.length === 0) &&
      (!incomingLinksByDoc.has(d.id) || incomingLinksByDoc.get(d.id)!.length === 0)
    )
  }, [documents, outgoingLinksByDoc, incomingLinksByDoc])

  // Filter roots to only those that actually have children (so we don't duplicate unlinked docs)
  const trueRoots = roots.filter(r => incomingLinksByDoc.has(r.id) && incomingLinksByDoc.get(r.id)!.length > 0)

  // DAG tracking to avoid infinite loops and duplicate deep rendering
  const renderedIds = new Set<string>()

  const renderNode = (doc: any, depth: number = 0, incomingLink?: any) => {
    const isDuplicate = renderedIds.has(doc.id)
    if (!isDuplicate) renderedIds.add(doc.id)

    const childrenLinks = incomingLinksByDoc.get(doc.id) || []
    
    // Also find pending links that are waiting FOR this doc? No, pending links are outgoing from the child, and they have to_doc_id = null.
    // So to show a pending link, we look at children that have outgoing links where to_doc_id is null.
    // Actually, pending links don't have to_doc_id. So we can't find them via incomingLinksByDoc.
    // Let's find pending outgoing links from THIS doc to show placeholders? 
    const pendingOutgoing = (outgoingLinksByDoc.get(doc.id) || []).filter(l => !l.to_doc_id)

    return (
      <div key={`${doc.id}-${depth}`} className="relative">
        <div className={`flex gap-4 ${depth > 0 ? 'mt-4' : 'mt-6'}`}>
          
          {/* Indentation Line */}
          {depth > 0 && (
            <div className="w-8 shrink-0 flex flex-col items-end">
              <div className="w-px h-full bg-[--border-subtle] -mr-[0.5px]"></div>
              <div className="w-full h-px bg-[--border-subtle] mt-5"></div>
            </div>
          )}

          {/* Node Card */}
          <div className="flex-1 min-w-0">
            {incomingLink && (
              <div className="flex items-center gap-2 mb-1.5 ml-1">
                <Badge variant={incomingLink.status === 'pending' ? 'warning' : 'muted'} className="text-[10px] h-5 py-0 border-dashed">
                  {incomingLink.status === 'pending' && <AlertCircle size={10} className="mr-1" />}
                  {incomingLink.link_type.replace('_', ' ')}
                </Badge>
                {incomingLink.status === 'pending' && (
                  <Button variant="ghost" size="sm" className="h-5 text-[10px] px-2 text-[--primary]">Confirm Match</Button>
                )}
              </div>
            )}

            {isDuplicate ? (
              <div 
                className="p-3 rounded-lg border border-dashed border-[--border-strong] bg-[--bg-muted]/50 flex items-center gap-2 text-sm text-[--text-secondary] cursor-pointer hover:bg-[--bg-surface] transition-colors"
                onClick={() => onSelectDoc?.(doc.id)}
              >
                <LinkIcon size={14} />
                <span>Also linked here: <strong>{doc.reference_number || doc.doc_type || 'Document'}</strong> (see above)</span>
              </div>
            ) : (
              <div 
                className={`flex flex-col p-4 rounded-lg border shadow-sm transition-colors cursor-pointer ${
                  selectedDocId === doc.id 
                    ? 'border-[--primary] bg-[--primary]/5 ring-1 ring-[--primary]/20' 
                    : doc.status === 'needs_review' 
                      ? 'border-amber-500/40 bg-[--warning-muted]/30 hover:border-amber-500' 
                      : 'border-[--border-subtle] bg-[--bg-surface] hover:border-[--border-default]'
                }`}
                onClick={() => onSelectDoc?.(doc.id)}
              >
                <div className="flex items-start justify-between gap-4">
                  <div className="flex flex-col gap-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-[--text-primary] truncate">{doc.reference_number || doc.storage_path.split('/').pop()}</span>
                      {doc.doc_type && (
                        <Badge variant="muted" className="text-[10px] tracking-wider uppercase h-5">{doc.doc_type}</Badge>
                      )}
                    </div>
                    {!compact && (
                      <p className="text-sm text-[--text-muted] line-clamp-2 mt-1">
                        {doc.summary || 'No summary available.'}
                      </p>
                    )}
                  </div>
                  <div className="flex flex-col items-end gap-2 shrink-0">
                    <span className="text-xs font-medium text-[--text-muted]">
                      {doc.doc_date ? new Date(doc.doc_date).toLocaleDateString() : 'Unknown date'}
                    </span>
                    <Badge variant={
                      doc.status === 'processing' ? 'muted' :
                      doc.status === 'needs_review' ? 'warning' : 'default'
                    }>
                      {doc.status.replace('_', ' ')}
                    </Badge>
                  </div>
                </div>

                {doc.status === 'needs_review' && doc.review_reason && (
                  <div className="flex items-start gap-2 mt-3 p-2.5 rounded-md bg-[--warning-muted] border border-amber-500/20 text-[--warning] text-xs">
                    <AlertCircle size={14} className="shrink-0 mt-0.5" />
                    <p>{doc.review_reason}</p>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>

        {/* Children (only if not duplicate) */}
        {!isDuplicate && (
          <div className={`ml-8 border-l border-[--border-subtle] pl-4 pb-2 ${childrenLinks.length === 0 && pendingOutgoing.length === 0 ? 'border-transparent' : ''}`}>
            {childrenLinks.map(link => {
              const childDoc = documents.find(d => d.id === link.from_doc_id)
              if (!childDoc) return null
              return renderNode(childDoc, depth + 1, link)
            })}
            
            {pendingOutgoing.map(pendingLink => (
              <div key={pendingLink.id} className="flex gap-4 mt-4 opacity-70">
                <div className="w-8 shrink-0 flex flex-col items-end">
                  <div className="w-px h-full bg-[--border-subtle] -mr-[0.5px]"></div>
                  <div className="w-full h-px bg-[--border-subtle] mt-5"></div>
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1.5 ml-1">
                    <Badge variant="muted" className="text-[10px] h-5 border-dashed border-[--text-muted] text-[--text-muted]">
                      {pendingLink.link_type.replace('_', ' ')}
                    </Badge>
                  </div>
                  <div className="p-3 rounded-lg border border-dashed border-[--border-strong] bg-[--bg-muted]/50 flex items-center gap-3 text-sm text-[--text-secondary]">
                    <Clock size={16} className="text-[--text-muted]" />
                    <span className="italic">Waiting for document: <strong>{pendingLink.pending_ref_number}</strong></span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    )
  }

  return (
    <div className="flex flex-col">
      <div className="flex items-center justify-between mb-4 border-b border-[--border-subtle] pb-3">
        <div className="flex items-center gap-2">
          <Clock size={18} className="text-[--text-muted]" />
          <h2 className="text-lg font-medium text-[--text-primary]">Litigation Timeline</h2>
        </div>
        <Button variant="outline" size="sm" onClick={() => setCompact(!compact)}>
          {compact ? 'Show Details' : 'Compact View'}
        </Button>
      </div>

      <div className="flex flex-col gap-6">
        {trueRoots.length === 0 && unlinked.length === 0 ? (
          <div className="py-12 text-center text-[--text-muted] border border-dashed border-[--border-strong] rounded-lg">
            <p>No proceeding documents found in this matter.</p>
          </div>
        ) : (
          <>
            {trueRoots.map(root => renderNode(root, 0))}
            
            {unlinked.length > 0 && (
              <div className="mt-8 pt-6 border-t border-[--border-subtle]">
                <div className="flex items-center gap-2 mb-4">
                  <FileText size={16} className="text-[--text-muted]" />
                  <h3 className="text-sm font-semibold text-[--text-secondary] uppercase tracking-wider">Unlinked Documents</h3>
                  <Badge variant="muted" className="ml-2">{unlinked.length}</Badge>
                </div>
                <div className="grid gap-3">
                  {unlinked.map(doc => (
                    <div 
                      key={doc.id} 
                      className={`flex flex-col p-4 rounded-lg border transition-all cursor-pointer ${
                        selectedDocId === doc.id
                          ? 'border-[--primary] bg-[--primary]/5 ring-1 ring-[--primary]/20'
                          : 'border-[--border-subtle] bg-[--bg-surface] opacity-90 hover:opacity-100 hover:border-[--border-default]'
                      }`}
                      onClick={() => onSelectDoc?.(doc.id)}
                    >
                      <div className="flex items-start justify-between gap-4">
                        <div className="flex flex-col gap-1 min-w-0">
                          <span className="font-medium text-[--text-primary] text-sm truncate">{doc.reference_number || doc.storage_path.split('/').pop()}</span>
                          {doc.doc_type && <span className="text-[10px] text-[--text-muted] font-medium">{doc.doc_type}</span>}
                        </div>
                        <span className="text-xs text-[--text-muted]">{doc.doc_date ? new Date(doc.doc_date).toLocaleDateString() : 'No date'}</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}
