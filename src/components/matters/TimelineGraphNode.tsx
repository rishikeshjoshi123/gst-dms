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
        {/*
          CRITICAL: outer wrapper must NOT have overflow:hidden — handles extend
          outside the card boundary and overflow:hidden clips them invisible.
        */}
        <div className="relative w-52 group" style={{ filter: selected ? `drop-shadow(0 0 8px ${colors.accent}50)` : undefined }}>

          {/* TARGET handle — top, appears as a subtle notch/port */}
          <Handle
            type="target"
            position={Position.Top}
            isConnectable={isConnectable}
            style={{
              width: 20,
              height: 6,
              background: colors.accent,
              border: 'none',
              borderRadius: '0 0 4px 4px',
              top: 0,
              opacity: 0.7,
              cursor: 'crosshair',
              zIndex: 10,
              transition: 'opacity 0.2s, height 0.2s',
            }}
          />

          {/* Card — paper document aesthetic */}
          <div
            className={`flex flex-col overflow-hidden shadow-md transition-shadow duration-200 ${
              selected
                ? 'shadow-[0_4px_20px_rgba(0,0,0,0.15)] ring-2 ring-offset-0'
                : 'hover:shadow-[0_6px_24px_rgba(0,0,0,0.13)]'
            }`}
            style={{
              borderRadius: '6px 2px 6px 6px', // slight sharp on top-right for fold effect
              background: 'var(--surface)',
              border: `1px solid ${selected ? colors.accent : 'var(--border)'}`,
              marginTop: '0px',
            }}
          >
            {/* Colored header stripe with doc type */}
            <div
              className="flex items-center justify-between px-3 py-2 relative"
              style={{ background: `${colors.accent}18` }}
            >
              {/* Thin left accent bar */}
              <div
                className="absolute left-0 top-0 bottom-0 w-[3px] rounded-l"
                style={{ background: colors.accent }}
              />

              <span
                className="text-[11px] font-black uppercase tracking-widest pl-1 truncate"
                style={{ color: colors.accent }}
              >
                {doc.doc_type?.replace(/_/g, '-') || 'UNKNOWN'}
              </span>

              <div className="flex items-center gap-1 shrink-0 ml-2">
                {isNeedsReview && <AlertTriangle size={11} className="text-amber-500" />}
                {isSupporting && (
                  <span className="text-[8px] font-bold uppercase tracking-wider text-slate-400 bg-slate-100 dark:bg-slate-800 dark:text-slate-500 px-1 rounded">
                    SUP
                  </span>
                )}
                {/* Paper fold corner */}
                <div
                  className="w-3 h-3 shrink-0"
                  style={{
                    background: `conic-gradient(from 225deg at 100% 0%, var(--surface) 90deg, ${colors.accent}25 90deg)`,
                    borderBottom: '1px solid var(--border)',
                    borderLeft: '1px solid var(--border)',
                    borderBottomLeftRadius: '3px',
                  }}
                />
              </div>
            </div>

            {/* Body */}
            <div className="px-3 py-2.5">
              {/* Reference number — the main identifier */}
              <p className="text-[13px] font-semibold text-[var(--text-primary)] font-mono truncate leading-tight">
                {doc.reference_number || doc.storage_path?.split('/').pop() || '—'}
              </p>

              {/* Date */}
              <div className="flex items-center gap-1 mt-1.5 text-[10px] text-[var(--text-muted)]">
                <Calendar size={9} className="shrink-0" style={{ color: colors.accent, opacity: 0.6 }} />
                <span>{doc.doc_date ? new Date(doc.doc_date).toISOString().split('T')[0] : 'Unknown date'}</span>
              </div>
            </div>
          </div>

          {/* SOURCE handle — bottom, appears as a subtle port */}
          <Handle
            type="source"
            position={Position.Bottom}
            isConnectable={isConnectable}
            style={{
              width: 20,
              height: 6,
              background: 'var(--text-muted)',
              border: 'none',
              borderRadius: '4px 4px 0 0',
              bottom: 0,
              opacity: 0.45,
              cursor: 'crosshair',
              zIndex: 10,
              transition: 'opacity 0.2s',
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
