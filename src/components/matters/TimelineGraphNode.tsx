import React, { memo } from 'react'
import { Handle, Position } from '@xyflow/react'
import { Badge } from '@/components/ui/badge'
import { FileText, Link as LinkIcon, ExternalLink, Calendar, Info, AlertTriangle } from 'lucide-react'
import {
  HoverCard,
  HoverCardContent,
  HoverCardTrigger,
} from "@/components/ui/hover-card"

// Color palette per document type
// Each entry: [accent hex, light bg (light mode), dark bg (dark mode), text color class]
const DOC_TYPE_COLORS: Record<string, {
  accent: string
  bgLight: string
  bgDark: string
  textClass: string
  borderClass: string
}> = {
  SCN:          { accent: '#EF4444', bgLight: '#FEF2F2', bgDark: '#450a0a30', textClass: 'text-red-600 dark:text-red-400',       borderClass: 'border-l-red-500' },
  OIO:          { accent: '#DC2626', bgLight: '#FEF2F2', bgDark: '#450a0a30', textClass: 'text-red-700 dark:text-red-300',       borderClass: 'border-l-red-600' },
  OIA:          { accent: '#EA580C', bgLight: '#FFF7ED', bgDark: '#431407 30', textClass: 'text-orange-600 dark:text-orange-400', borderClass: 'border-l-orange-500' },
  'DRC-01':     { accent: '#D97706', bgLight: '#FFFBEB', bgDark: '#45200030', textClass: 'text-amber-600 dark:text-amber-400',   borderClass: 'border-l-amber-500' },
  'DRC-01A':    { accent: '#D97706', bgLight: '#FFFBEB', bgDark: '#45200030', textClass: 'text-amber-600 dark:text-amber-400',   borderClass: 'border-l-amber-500' },
  'DRC-01C':    { accent: '#CA8A04', bgLight: '#FFFBEB', bgDark: '#45200030', textClass: 'text-yellow-600 dark:text-yellow-400', borderClass: 'border-l-yellow-500' },
  'DRC-07':     { accent: '#B45309', bgLight: '#FEF3C7', bgDark: '#45200030', textClass: 'text-amber-700 dark:text-amber-300',   borderClass: 'border-l-amber-600' },
  'DRC-03':     { accent: '#92400E', bgLight: '#FEF3C7', bgDark: '#45200030', textClass: 'text-amber-800 dark:text-amber-200',   borderClass: 'border-l-amber-700' },
  'APL-01':     { accent: '#2563EB', bgLight: '#EFF6FF', bgDark: '#0c1a4030', textClass: 'text-blue-600 dark:text-blue-400',    borderClass: 'border-l-blue-500' },
  'APL-02':     { accent: '#1D4ED8', bgLight: '#EFF6FF', bgDark: '#0c1a4030', textClass: 'text-blue-700 dark:text-blue-300',    borderClass: 'border-l-blue-600' },
  'APL-04':     { accent: '#1E40AF', bgLight: '#EFF6FF', bgDark: '#0c1a4030', textClass: 'text-blue-800 dark:text-blue-200',    borderClass: 'border-l-blue-700' },
  'APL-05':     { accent: '#3B82F6', bgLight: '#EFF6FF', bgDark: '#0c1a4030', textClass: 'text-blue-500 dark:text-blue-400',    borderClass: 'border-l-blue-400' },
  STAY:         { accent: '#7C3AED', bgLight: '#F5F3FF', bgDark: '#1e0a4030', textClass: 'text-violet-600 dark:text-violet-400', borderClass: 'border-l-violet-500' },
  REPLY:        { accent: '#0891B2', bgLight: '#ECFEFF', bgDark: '#0a2a3030', textClass: 'text-cyan-600 dark:text-cyan-400',    borderClass: 'border-l-cyan-500' },
  HC_PETITION:  { accent: '#0284C7', bgLight: '#F0F9FF', bgDark: '#0a2a3030', textClass: 'text-sky-600 dark:text-sky-400',      borderClass: 'border-l-sky-500' },
  HC_ORDER:     { accent: '#0369A1', bgLight: '#F0F9FF', bgDark: '#0a2a3030', textClass: 'text-sky-700 dark:text-sky-300',      borderClass: 'border-l-sky-600' },
  SC_PETITION:  { accent: '#4F46E5', bgLight: '#EEF2FF', bgDark: '#1a1a4030', textClass: 'text-indigo-600 dark:text-indigo-400', borderClass: 'border-l-indigo-500' },
  SC_ORDER:     { accent: '#4338CA', bgLight: '#EEF2FF', bgDark: '#1a1a4030', textClass: 'text-indigo-700 dark:text-indigo-300', borderClass: 'border-l-indigo-600' },
  OTHER:        { accent: '#6B7280', bgLight: '#F9FAFB', bgDark: '#11182730', textClass: 'text-gray-500 dark:text-gray-400',    borderClass: 'border-l-gray-400' },
}

const DEFAULT_COLORS = { accent: '#6B7280', bgLight: '#F9FAFB', bgDark: '#11182730', textClass: 'text-gray-500 dark:text-gray-400', borderClass: 'border-l-gray-400' }

function getDocTypeColors(docType?: string) {
  if (!docType) return DEFAULT_COLORS
  return DOC_TYPE_COLORS[docType] || DEFAULT_COLORS
}

export const TimelineGraphNode = memo(({ data, isConnectable }: any) => {
  const { doc, selected } = data
  const isSupporting = doc.document_class === 'supporting'
  const isNeedsReview = doc.status === 'needs_review'
  const colors = getDocTypeColors(doc.doc_type)

  return (
    <HoverCard openDelay={200} closeDelay={100}>
      <HoverCardTrigger asChild>
        <div
          className={`flex flex-col rounded-xl border-l-4 shadow-md transition-all cursor-pointer w-56 relative overflow-hidden ${colors.borderClass} ${
            selected
              ? 'border-t border-r border-b border-[var(--primary)] bg-blue-50/80 dark:bg-blue-950/50 ring-2 ring-blue-500/30 shadow-[0_4px_20px_rgba(37,99,235,0.2)]'
              : isNeedsReview
                ? 'border-t border-r border-b border-amber-400/60 bg-amber-50/70 dark:bg-amber-950/30 hover:shadow-[0_4px_16px_rgba(245,158,11,0.2)] hover:-translate-y-0.5'
                : isSupporting
                  ? 'border-t border-r border-b border-[var(--border-strong)] bg-slate-50 dark:bg-[var(--surface-hover)] hover:shadow-[0_4px_16px_rgba(0,0,0,0.12)] hover:-translate-y-0.5'
                  : 'border-t border-r border-b border-[var(--border)] bg-[var(--surface)] hover:shadow-[0_4px_16px_rgba(0,0,0,0.12)] hover:-translate-y-0.5'
          }`}
          style={{ transition: 'box-shadow 0.2s, transform 0.15s' }}
        >
          {/* Doc fold corner */}
          <div className="absolute top-0 right-0 w-3.5 h-3.5 bg-[var(--surface-hover)] border-b border-l border-[var(--border-strong)] rounded-bl-sm" />

          {/* TARGET handle — top center, large & easy to grab */}
          <Handle
            type="target"
            position={Position.Top}
            isConnectable={isConnectable}
            style={{
              width: 14,
              height: 14,
              background: colors.accent,
              border: '2px solid white',
              borderRadius: '50%',
              top: -7,
              boxShadow: `0 0 0 3px ${colors.accent}30`,
              cursor: 'crosshair',
            }}
          />

          <div className="p-3 pb-2.5">
            {/* Doc type chip + title row */}
            <div className="flex items-start justify-between gap-2 pr-3 mb-1.5">
              <div className="flex flex-col gap-0.5 min-w-0 flex-1">
                {/* Colored document type label */}
                <span className={`font-black text-sm uppercase tracking-wider truncate leading-none ${colors.textClass}`}>
                  {doc.doc_type?.replace(/_/g, '-') || 'UNKNOWN'}
                </span>
                {isSupporting && (
                  <Badge variant="outline" className="text-[9px] tracking-wider uppercase h-4 px-1 py-0 w-fit bg-slate-100 text-slate-500 border-slate-300 mt-0.5">
                    Supporting
                  </Badge>
                )}
              </div>
              {isNeedsReview && (
                <AlertTriangle size={13} className="text-amber-500 shrink-0 mt-0.5" />
              )}
            </div>

            {/* Reference number */}
            <span className="text-[11px] text-[--text-secondary] font-mono truncate block leading-snug">
              {doc.reference_number || doc.storage_path?.split('/').pop() || 'No reference'}
            </span>

            {/* Date row */}
            <div className="flex items-center gap-1.5 text-[10px] text-[--text-muted] mt-2 font-medium">
              <Calendar size={10} className="text-slate-400 shrink-0" />
              <span>{doc.doc_date ? new Date(doc.doc_date).toISOString().split('T')[0] : 'Unknown date'}</span>
              {doc.raw_metadata?.financial_year && (
                <>
                  <span className="text-[var(--border-strong)]">·</span>
                  <span className={`text-[9px] font-bold uppercase ${colors.textClass} opacity-70`}>
                    {doc.raw_metadata.financial_year}
                  </span>
                </>
              )}
            </div>
          </div>

          {/* SOURCE handle — bottom center, large & easy to grab */}
          <Handle
            type="source"
            position={Position.Bottom}
            isConnectable={isConnectable}
            style={{
              width: 14,
              height: 14,
              background: '#64748b',
              border: '2px solid white',
              borderRadius: '50%',
              bottom: -7,
              boxShadow: '0 0 0 3px rgba(100,116,139,0.25)',
              cursor: 'crosshair',
            }}
          />
        </div>
      </HoverCardTrigger>
      
      <HoverCardContent side="right" align="start" className="w-80 p-4 shadow-[var(--shadow-xl)] z-[100] bg-[var(--surface)] border-[var(--border-strong)] rounded-xl">
        <div className="flex justify-between items-start mb-3">
          <div className="flex items-center gap-2">
            <div
              className="w-2.5 h-2.5 rounded-full shrink-0"
              style={{ backgroundColor: colors.accent }}
            />
            <h4 className="text-sm font-semibold text-[var(--text-primary)] break-words pr-2">
              <span className={`font-black uppercase ${colors.textClass}`}>{doc.doc_type?.toUpperCase() || 'DOCUMENT'}</span>
              <span className="block text-xs font-normal text-[var(--text-secondary)] font-mono mt-0.5">
                {doc.reference_number || doc.storage_path?.split('/').pop()}
              </span>
            </h4>
          </div>
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
