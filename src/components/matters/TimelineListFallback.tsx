'use client'

import React, { useMemo } from 'react'
import { FileText, Loader2, AlertTriangle, Link as LinkIcon, Info } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import { formatDistanceToNow } from 'date-fns'

const DOC_TYPE_COLORS: Record<string, string> = {
  SCN: 'bg-[var(--danger-muted)] text-[var(--danger)] border-[var(--danger)]',
  OIO: 'bg-[var(--danger-muted)] text-[var(--danger)] border-[var(--danger)]',
  OIA: 'bg-[var(--danger-muted)] text-[var(--danger)] border-[var(--danger)]',
  'DRC-01': 'bg-[var(--danger-muted)] text-[var(--danger)] border-[var(--danger)]',
  'DRC-07': 'bg-[var(--danger-muted)] text-[var(--danger)] border-[var(--danger)]',
  'DRC-03': 'bg-[var(--danger-muted)] text-[var(--danger)] border-[var(--danger)]',
  'APL-01': 'bg-[var(--primary)]/10 text-[var(--primary)] border-[var(--primary)]',
  STAY: 'bg-[var(--success-muted)] text-[var(--success)] border-[var(--success)]',
  REPLY: 'bg-[var(--success-muted)] text-[var(--success)] border-[var(--success)]',
}

const DEFAULT_COLOR = 'bg-[var(--surface-hover)] text-[var(--text-secondary)] border-[var(--border-strong)]'

export interface TimelineDocument {
  id: string
  status?: string | null
  doc_type?: string | null
  document_class?: string | null
  storage_path?: string | null
  created_at: string
  financial_year?: string | null
  raw_metadata?: {
    date?: string | null
    reference_number?: string | null
    summary?: string | null
    financial_year?: string | null
  } | null
}

export interface TimelineLink {
  from_doc_id?: string | null
  to_doc_id?: string | null
}

function getDocTypeColor(docType?: string | null) {
  if (!docType) return DEFAULT_COLOR
  return DOC_TYPE_COLORS[docType] || DEFAULT_COLOR
}

export function TimelineListFallback({
  documents,
  links,
  selectedDocId,
  onSelectDoc
}: {
  documents: TimelineDocument[]
  links: TimelineLink[]
  selectedDocId?: string | null
  onSelectDoc?: (id: string) => void
}) {
  // Sort documents by date (newest first based on raw_metadata.date or created_at)
  const sortedDocuments = useMemo(() => {
    return [...documents].sort((a, b) => {
      const dateA = a.raw_metadata?.date ? new Date(a.raw_metadata.date).getTime() : new Date(a.created_at).getTime()
      const dateB = b.raw_metadata?.date ? new Date(b.raw_metadata.date).getTime() : new Date(b.created_at).getTime()
      return dateB - dateA
    })
  }, [documents])

  return (
    <div className="flex flex-col h-full bg-[var(--surface)] overflow-hidden">
      <div className="px-4 py-3 border-b border-[var(--border)] bg-[var(--bg)] shrink-0">
        <h2 className="text-sm font-bold text-[var(--text-primary)] uppercase tracking-wider">
          Timeline Documents ({documents.length})
        </h2>
      </div>
      
      <div className="flex-1 overflow-y-auto p-3 space-y-3 custom-scrollbar">
        {sortedDocuments.map(doc => {
          const isSelected = selectedDocId === doc.id
          const typeColor = getDocTypeColor(doc.doc_type)
          const docLinks = links.filter(l => l.from_doc_id === doc.id || l.to_doc_id === doc.id)
          const isProcessing = doc.status === 'processing' || doc.status === 'uploaded'
          const isFailed = doc.status === 'failed'
          
          return (
            <button
              type="button"
              key={doc.id}
              onClick={() => onSelectDoc?.(doc.id)}
              aria-pressed={isSelected}
              className={cn(
                "flex w-full flex-col p-3.5 rounded-[var(--radius-md)] cursor-pointer text-left transition-colors border",
                isSelected
                  ? "bg-[var(--primary)]/5 border-[var(--primary)] shadow-sm"
                  : "bg-[var(--surface)] border-[var(--border)] hover:border-[var(--border-strong)]"
              )}
            >
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <span className={cn(
                    "w-20 text-center text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-[var(--radius-sm)]",
                    typeColor
                  )}>
                    {doc.doc_type || 'UNKNOWN'}
                  </span>
                  {doc.document_class === 'supporting' && (
                    <Badge variant="muted" className="text-[9px] uppercase tracking-wider h-5 px-1.5 border-[var(--border)]">
                      Supporting
                    </Badge>
                  )}
                </div>
                <div className="flex items-center gap-1.5">
                  {isProcessing && <Loader2 size={12} className="animate-spin text-[var(--primary)]" />}
                  {isFailed && <AlertTriangle size={12} className="text-[var(--danger)]" />}
                  <span className="text-[10px] text-[var(--text-muted)]">
                    {doc.raw_metadata?.date 
                      ? new Date(doc.raw_metadata.date).toLocaleDateString() 
                      : formatDistanceToNow(new Date(doc.created_at), { addSuffix: true })}
                  </span>
                </div>
              </div>
              
              <div className="text-[13px] font-semibold text-[var(--text-primary)] truncate mb-1">
                {doc.raw_metadata?.reference_number || doc.storage_path?.split('/').pop() || 'Untitled document'}
              </div>
              
              {doc.raw_metadata?.summary && (
                <p className="text-xs text-[var(--text-secondary)] line-clamp-2 mb-2">
                  {doc.raw_metadata.summary}
                </p>
              )}
              
              <div className="mt-2 pt-2 border-t border-[var(--border)] flex items-center justify-between">
                <div className="flex items-center gap-1.5 text-[10px] text-[var(--text-muted)] font-mono">
                  <FileText size={10} />
                  {doc.financial_year || doc.raw_metadata?.financial_year || 'No FY'}
                </div>
                {docLinks.length > 0 && (
                  <div className="flex items-center gap-1 text-[10px] font-medium text-[var(--primary)]">
                    <LinkIcon size={10} />
                    {docLinks.length} {docLinks.length === 1 ? 'Link' : 'Links'}
                  </div>
                )}
              </div>
            </button>
          )
        })}
        {documents.length === 0 && (
          <div className="py-10 text-center flex flex-col items-center">
            <Info size={24} className="text-[var(--text-muted)] mb-2" />
            <p className="text-sm text-[var(--text-muted)]">No documents in timeline</p>
          </div>
        )}
      </div>
    </div>
  )
}
