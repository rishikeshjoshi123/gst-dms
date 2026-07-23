import React, { memo } from 'react'
import { Handle, Position } from '@xyflow/react'
import { Badge } from '@/components/ui/badge'
import { FileText, Link as LinkIcon, ExternalLink, Calendar, Info } from 'lucide-react'
import {
  HoverCard,
  HoverCardContent,
  HoverCardTrigger,
} from "@/components/ui/hover-card"

export const TimelineGraphNode = memo(({ data, isConnectable }: any) => {
  const { doc, selected } = data
  const isSupporting = doc.document_class === 'supporting'
  const isNeedsReview = doc.status === 'needs_review'

  return (
    <HoverCard openDelay={200} closeDelay={100}>
      <HoverCardTrigger asChild>
        <div
          className={`flex flex-col p-3 rounded-lg border shadow-sm transition-all cursor-pointer w-56 relative overflow-hidden ${
            selected
              ? 'border-[var(--primary)] bg-blue-50/60 dark:bg-blue-950/40 ring-2 ring-blue-500/30 shadow-[var(--shadow-md)]'
              : isNeedsReview
                ? 'border-amber-500/50 bg-amber-50/60 dark:bg-amber-950/30 dark:border-amber-500/40 hover:border-amber-500 hover:shadow-md'
                : isSupporting
                  ? 'border-[var(--border-strong)] dark:border-[var(--border-strong)] bg-slate-50 dark:bg-[var(--surface-hover)] hover:border-[var(--primary)] hover:shadow-md'
                  : 'border-[var(--border)] dark:border-[var(--border-strong)] bg-[var(--surface)] hover:border-[var(--primary)] hover:shadow-md'
          }`}
        >
          {/* Document Fold Effect */}
          <div className="absolute top-0 right-0 w-3.5 h-3.5 bg-[var(--surface-hover)] border-b border-l border-[var(--border-strong)] rounded-bl-sm shadow-[-1px_1px_2px_rgba(0,0,0,0.05)]" />

          <Handle
            type="target"
            position={Position.Top}
            isConnectable={isConnectable}
            className="w-2 h-2 !bg-[--border-strong]"
          />
          
          <div className="flex items-start justify-between gap-2 mb-2 pr-2">
            <div className="flex flex-col gap-1 min-w-0">
              <div className="flex items-center gap-1.5 flex-wrap">
                <span className="font-bold text-[--text-primary] truncate text-sm uppercase tracking-wide">
                  {doc.doc_type?.replace('_', ' ') || 'Unknown Type'}
                </span>
                {isSupporting && (
                  <Badge variant="outline" className="text-[9px] tracking-wider uppercase h-4 px-1 py-0 bg-slate-100 text-slate-600 border-slate-300">
                    Supporting
                  </Badge>
                )}
              </div>
              <span className="text-[11px] text-[--text-secondary] font-mono truncate">
                {doc.reference_number || doc.storage_path?.split('/').pop() || 'No reference'}
              </span>
            </div>
            {isSupporting && (
              <FileText size={14} className="text-slate-400 shrink-0 mt-0.5" />
            )}
          </div>

          <div className="flex items-center gap-1.5 text-[10px] text-[--text-muted] mt-1 font-medium">
            <Calendar size={11} className="text-slate-400" />
            <span>{doc.doc_date ? new Date(doc.doc_date).toISOString().split('T')[0] : 'Unknown date'}</span>
          </div>

          <Handle
            type="source"
            position={Position.Bottom}
            isConnectable={isConnectable}
            className="w-2 h-2 !bg-slate-400 border-none"
          />
        </div>
      </HoverCardTrigger>
      
      <HoverCardContent side="right" align="start" className="w-80 p-4 shadow-[var(--shadow-xl)] z-[100] bg-[var(--surface)] border-[var(--border-strong)] rounded-xl">
        <div className="flex justify-between items-start mb-3">
          <h4 className="text-sm font-semibold text-[var(--text-primary)] break-words pr-2">
            {doc.doc_type?.toUpperCase() || 'DOCUMENT'}
            <span className="block text-xs font-normal text-[var(--text-secondary)] font-mono mt-1">
              {doc.reference_number || doc.storage_path?.split('/').pop()}
            </span>
          </h4>
          <a 
            href={`/matters/${doc.matter_id}/documents/${doc.id}`}
            onClick={(e) => e.stopPropagation()}
            className="inline-flex shrink-0 items-center justify-center rounded-md text-[10px] font-semibold uppercase tracking-wider h-5 px-2 gap-1 bg-[--bg-muted] text-[--text-secondary] hover:bg-[--border-strong] hover:text-[--text-primary] transition-colors ml-2"
          >
            <ExternalLink size={10} /> View
          </a>
        </div>
        
        {doc.raw_metadata && (
          <div className="grid grid-cols-2 gap-2 mb-4 text-xs">
            {doc.raw_metadata.financial_year && (
              <div className="flex flex-col bg-[var(--bg)] p-1.5 rounded border border-[var(--border)]">
                <span className="text-[9px] font-bold text-[var(--text-muted)] uppercase tracking-wider">Financial Year</span>
                <span className="font-medium text-[var(--text-primary)]">{doc.raw_metadata.financial_year}</span>
              </div>
            )}
            {doc.raw_metadata.extracted_amounts?.total_demand && (
              <div className="flex flex-col bg-[var(--bg)] p-1.5 rounded border border-[var(--border)]">
                <span className="text-[9px] font-bold text-[var(--text-muted)] uppercase tracking-wider">Total Demand</span>
                <span className="font-medium text-red-600 dark:text-red-400">₹{Number(doc.raw_metadata.extracted_amounts.total_demand).toLocaleString('en-IN')}</span>
              </div>
            )}
          </div>
        )}

        {doc.summary && (
          <p className="text-xs text-[var(--text-secondary)] mb-4 leading-relaxed line-clamp-2 italic border-l-2 border-[var(--border)] pl-2">
            {doc.summary}
          </p>
        )}

        {isNeedsReview && doc.review_reason && (
          <div className="flex items-start gap-2 mb-3 p-2 rounded-md bg-[--warning-muted] border border-amber-500/20 text-[--warning] text-xs">
            <Info size={14} className="shrink-0 mt-0.5" />
            <p className="line-clamp-3">{doc.review_reason}</p>
          </div>
        )}

        <div className="flex items-center justify-between text-xs text-[--text-muted] border-t border-[--border-subtle] pt-3">
          <span className="flex items-center gap-1">
            <Calendar size={12} />
            {doc.doc_date ? new Date(doc.doc_date).toISOString().split('T')[0] : 'Unknown date'}
          </span>
          <Badge variant={
            doc.status === 'processing' ? 'muted' :
            doc.status === 'needs_review' ? 'warning' : 'default'
          }>
            {doc.status.replace('_', ' ')}
          </Badge>
        </div>
      </HoverCardContent>
    </HoverCard>
  )
})
