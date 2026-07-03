'use client'

import { X, FileText, Calendar, ExternalLink } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'

export function TimelineDocumentDetail({ doc, onClose }: { doc: any, onClose: () => void }) {
  const metadata = doc.raw_metadata || {}

  // Get signed URL for the document (In a real app, this might call a server action or use supabase client directly if public)
  // Since we have supabase, let's construct a direct link to a server route that handles auth, 
  // or we can assume there's an API route like /api/documents/[id]/download
  const viewUrl = `/api/documents/${doc.id}/view`

  const renderValue = (val: any) => {
    if (val === null || val === undefined) return <span className="text-[--text-muted]">N/A</span>
    if (typeof val === 'boolean') return val ? 'Yes' : 'No'
    if (typeof val === 'string' || typeof val === 'number') return val
    if (Array.isArray(val)) {
      if (val.length === 0) return <span className="text-[--text-muted]">Empty</span>
      return (
        <ul className="list-disc list-inside">
          {val.map((item, i) => <li key={i}>{renderValue(item)}</li>)}
        </ul>
      )
    }
    if (typeof val === 'object') {
      return (
        <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-2 mt-1 mb-2 bg-[--bg-muted]/50 p-2 rounded text-sm">
          {Object.entries(val).map(([k, v]) => (
            <div key={k} className="flex flex-col">
              <dt className="text-xs font-semibold text-[--text-muted] capitalize tracking-wide">{k.replace(/_/g, ' ')}</dt>
              <dd className="text-[--text-primary] font-medium break-words mt-0.5">{renderValue(v)}</dd>
            </div>
          ))}
        </dl>
      )
    }
    return JSON.stringify(val)
  }

  return (
    <div className="flex flex-col h-full min-h-[600px] border border-[--border-subtle] bg-[--bg-surface] rounded-lg shadow-xl overflow-hidden">
      
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-[--border-subtle] bg-[--bg-muted]/20">
        <div className="flex items-center gap-3 min-w-0">
          <div className="p-2 rounded-md bg-[--primary]/10 text-[--primary]">
            <FileText size={20} />
          </div>
          <div className="flex flex-col min-w-0">
            <h3 className="text-base font-semibold text-[--text-primary] truncate pr-4">
              {doc.reference_number || doc.storage_path.split('/').pop()}
            </h3>
            <div className="flex items-center gap-2 mt-0.5">
              {doc.doc_type && <Badge variant="muted" className="text-[10px] uppercase h-4 px-1.5 py-0">{doc.doc_type}</Badge>}
              <span className="text-xs text-[--text-muted] flex items-center gap-1">
                <Calendar size={12} />
                {doc.doc_date ? new Date(doc.doc_date).toLocaleDateString() : 'Unknown date'}
              </span>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <a href={viewUrl} target="_blank" rel="noreferrer" className="inline-flex items-center justify-center rounded-md text-sm font-medium h-8 px-3 gap-1.5 bg-[--primary] text-white hover:bg-[--primary-hover] shadow-sm transition-colors">
            <ExternalLink size={14} />
            View PDF
          </a>
          <Button variant="ghost" size="icon" className="h-8 w-8 text-[--text-muted] hover:text-[--text-primary]" onClick={onClose}>
            <X size={16} />
          </Button>
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-5">
        <div className="flex flex-col gap-6">
          
          {/* Summary */}
          {doc.summary && (
            <div className="flex flex-col gap-2">
              <h4 className="text-sm font-semibold text-[--text-primary] border-b border-[--border-subtle] pb-1">AI Synopsis</h4>
              <p className="text-sm text-[--text-secondary] leading-relaxed">{doc.summary}</p>
            </div>
          )}

          {/* Extracted Metadata */}
          <div className="flex flex-col gap-3">
            <h4 className="text-sm font-semibold text-[--text-primary] border-b border-[--border-subtle] pb-1">Extracted Data</h4>
            
            {Object.keys(metadata).length === 0 ? (
              <p className="text-sm text-[--text-muted] italic">No metadata extracted.</p>
            ) : (
              <div className="grid grid-cols-1 gap-4">
                {Object.entries(metadata).map(([key, value]) => {
                  // Skip linking attributes in main view as they are visualized in the graph
                  if (key === 'chaining_attributes' || key === 'link_type') return null
                  
                  return (
                    <div key={key} className="flex flex-col gap-1.5">
                      <h5 className="text-xs font-semibold text-[--text-muted] uppercase tracking-wider">
                        {key.replace(/_/g, ' ')}
                      </h5>
                      <div className="text-sm text-[--text-primary]">
                        {renderValue(value)}
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </div>

          {/* System Info */}
          <div className="flex flex-col gap-3 pt-4 border-t border-[--border-subtle]">
            <h4 className="text-sm font-semibold text-[--text-primary] border-b border-[--border-subtle] pb-1">System Info</h4>
            <div className="grid grid-cols-2 gap-4">
              <div className="flex flex-col gap-1">
                <span className="text-xs font-semibold text-[--text-muted] uppercase tracking-wider">Status</span>
                <Badge variant={doc.status === 'needs_review' ? 'warning' : doc.status === 'failed' ? 'danger' : 'muted'} className="w-fit">{doc.status.replace('_', ' ')}</Badge>
              </div>
              <div className="flex flex-col gap-1">
                <span className="text-xs font-semibold text-[--text-muted] uppercase tracking-wider">Storage Path</span>
                <span className="text-xs font-mono text-[--text-secondary] break-all">{doc.storage_path}</span>
              </div>
              {doc.review_reason && (
                <div className="flex flex-col gap-1 col-span-2 mt-1 p-3 rounded-md bg-[--danger-muted] border border-[--danger] text-[--danger] text-xs">
                  <span className="font-semibold uppercase tracking-wider text-[10px]">Error Details</span>
                  <span className="leading-relaxed">{doc.review_reason}</span>
                </div>
              )}
            </div>
          </div>

        </div>
      </div>
    </div>
  )
}
