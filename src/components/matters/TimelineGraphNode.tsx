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
          Outer wrapper: NO overflow:hidden.
          Width 148px × ~175px content ≈ roughly document icon proportions.
        */}
        <div style={{ position: 'relative', width: 148 }}>

          {/* TOP HANDLE — target (child input), pill bar at very top */}
          <Handle
            type="target"
            position={Position.Top}
            isConnectable={isConnectable}
            style={{
              width: 24, height: 5,
              background: colors.accent,
              border: 'none',
              borderRadius: '0 0 3px 3px',
              top: 0, opacity: 0.6,
              cursor: 'crosshair', zIndex: 10,
            }}
          />

          {/*
            FILTER WRAPPER: drop-shadow applied here follows the clip-path
            pentagon shape of the inner card.
            Syntax: drop-shadow(offset-x offset-y blur color) — no spread param.
            Use a very small blur (0.5px) for the border effect.
          */}
          <div style={{
            filter: selected
              ? `drop-shadow(0 0 0.5px ${colors.accent}) drop-shadow(0 4px 14px ${colors.accent}45)`
              : 'drop-shadow(0 0 0.5px rgba(0,0,0,0.28)) drop-shadow(0 2px 8px rgba(0,0,0,0.10))',
            transition: 'filter 0.2s',
          }}>
            {/* CLIPPED CARD: pentagon clip = real dog-ear corner */}
            <div style={{
              clipPath: 'polygon(0 0, calc(100% - 24px) 0, 100% 24px, 100% 100%, 0 100%)',
              background: 'var(--surface)',
              position: 'relative',
            }}>

              {/*
                FOLD CREASE — a 24×24 div at top-right with a strong diagonal
                gradient. `to bottom left` means: top-right = first color (dark),
                bottom-left = transparent. The 50% hard stop creates a clean edge.
                This div is inside the clip so it's already constrained to the
                pentagon — no canvas background color needed.
              */}
              <div style={{
                position: 'absolute', top: 0, right: 0,
                width: 24, height: 24,
                background: 'linear-gradient(to bottom left, rgba(0,0,0,0.20) 50%, transparent 50%)',
                zIndex: 1,
              }} />

              {/* Colored accent stripe — stops before the fold */}
              <div style={{
                height: 3,
                background: colors.accent,
                width: 'calc(100% - 24px)',
              }} />

              {/* Card body */}
              <div style={{ padding: '8px 11px 11px 11px' }}>

                {/* Doc type label */}
                <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 6, paddingRight: 4 }}>
                  <span style={{
                    fontSize: 10, fontWeight: 800,
                    letterSpacing: '0.1em', textTransform: 'uppercase',
                    color: colors.accent, lineHeight: 1.1,
                    wordBreak: 'break-all',
                  }}>
                    {doc.doc_type?.replace(/_/g, '-') || 'UNKNOWN'}
                  </span>
                  {isNeedsReview && <AlertTriangle size={10} color="#F59E0B" style={{ flexShrink: 0, marginLeft: 4, marginTop: 1 }} />}
                </div>

                {/* Reference number — normal weight monospace */}
                <p style={{
                  fontSize: 11, fontWeight: 500,
                  fontFamily: 'ui-monospace, SFMono-Regular, monospace',
                  color: 'var(--text-primary)',
                  overflow: 'hidden', textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap', lineHeight: 1.4,
                  marginBottom: 6,
                }}>
                  {doc.reference_number || doc.storage_path?.split('/').pop() || '—'}
                </p>

                {/* Date + supporting badge */}
                <div style={{ display: 'flex', alignItems: 'center', gap: 3 }}>
                  <Calendar size={9} style={{ color: 'var(--text-muted)', flexShrink: 0 }} />
                  <span style={{ fontSize: 10, color: 'var(--text-muted)', fontVariantNumeric: 'tabular-nums' }}>
                    {doc.doc_date ? new Date(doc.doc_date).toISOString().split('T')[0] : 'Unknown'}
                  </span>
                  {isSupporting && (
                    <span style={{
                      fontSize: 7, fontWeight: 700, textTransform: 'uppercase',
                      color: 'var(--text-muted)', background: 'var(--bg)',
                      border: '1px solid var(--border)',
                      padding: '0 3px', borderRadius: 2, marginLeft: 2,
                    }}>SUP</span>
                  )}
                </div>

              </div>
            </div>
          </div>

          {/* BOTTOM HANDLE — source (parent output), pill bar at very bottom */}
          <Handle
            type="source"
            position={Position.Bottom}
            isConnectable={isConnectable}
            style={{
              width: 24, height: 5,
              background: 'var(--text-muted)',
              border: 'none',
              borderRadius: '3px 3px 0 0',
              bottom: 0, opacity: 0.4,
              cursor: 'crosshair', zIndex: 10,
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
