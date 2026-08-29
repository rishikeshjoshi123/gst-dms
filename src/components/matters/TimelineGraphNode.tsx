import React, { memo } from 'react'
import { Handle, Position } from '@xyflow/react'
import { Badge } from '@/components/ui/badge'
import { FileText, Link as LinkIcon, ExternalLink, Calendar, Info, AlertTriangle, Loader2, XCircle, Clock } from 'lucide-react'
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
  SCN:          { accent: 'var(--danger)', bgLight: 'var(--danger-muted)', bgDark: 'var(--danger-muted)', textClass: 'text-[var(--danger)]', borderClass: 'border-l-[var(--danger)]' },
  OIO:          { accent: 'var(--danger)', bgLight: 'var(--danger-muted)', bgDark: 'var(--danger-muted)', textClass: 'text-[var(--danger)]', borderClass: 'border-l-[var(--danger)]' },
  OIA:          { accent: 'var(--danger)', bgLight: 'var(--danger-muted)', bgDark: 'var(--danger-muted)', textClass: 'text-[var(--danger)]', borderClass: 'border-l-[var(--danger)]' },
  'DRC-01':     { accent: 'var(--danger)', bgLight: 'var(--danger-muted)', bgDark: 'var(--danger-muted)', textClass: 'text-[var(--danger)]', borderClass: 'border-l-[var(--danger)]' },
  'DRC-01A':    { accent: 'var(--danger)', bgLight: 'var(--danger-muted)', bgDark: 'var(--danger-muted)', textClass: 'text-[var(--danger)]', borderClass: 'border-l-[var(--danger)]' },
  'DRC-01C':    { accent: 'var(--danger)', bgLight: 'var(--danger-muted)', bgDark: 'var(--danger-muted)', textClass: 'text-[var(--danger)]', borderClass: 'border-l-[var(--danger)]' },
  'DRC-07':     { accent: 'var(--danger)', bgLight: 'var(--danger-muted)', bgDark: 'var(--danger-muted)', textClass: 'text-[var(--danger)]', borderClass: 'border-l-[var(--danger)]' },
  'DRC-03':     { accent: 'var(--danger)', bgLight: 'var(--danger-muted)', bgDark: 'var(--danger-muted)', textClass: 'text-[var(--danger)]', borderClass: 'border-l-[var(--danger)]' },
  'APL-01':     { accent: 'var(--primary)', bgLight: 'var(--primary)/10', bgDark: 'var(--primary)/10', textClass: 'text-[var(--primary)]', borderClass: 'border-l-[var(--primary)]' },
  'APL-02':     { accent: 'var(--primary)', bgLight: 'var(--primary)/10', bgDark: 'var(--primary)/10', textClass: 'text-[var(--primary)]', borderClass: 'border-l-[var(--primary)]' },
  'APL-04':     { accent: 'var(--primary)', bgLight: 'var(--primary)/10', bgDark: 'var(--primary)/10', textClass: 'text-[var(--primary)]', borderClass: 'border-l-[var(--primary)]' },
  'APL-05':     { accent: 'var(--primary)', bgLight: 'var(--primary)/10', bgDark: 'var(--primary)/10', textClass: 'text-[var(--primary)]', borderClass: 'border-l-[var(--primary)]' },
  STAY:         { accent: 'var(--success)', bgLight: 'var(--success-muted)', bgDark: 'var(--success-muted)', textClass: 'text-[var(--success)]', borderClass: 'border-l-[var(--success)]' },
  REPLY:        { accent: 'var(--success)', bgLight: 'var(--success-muted)', bgDark: 'var(--success-muted)', textClass: 'text-[var(--success)]', borderClass: 'border-l-[var(--success)]' },
  HC_PETITION:  { accent: 'var(--primary)', bgLight: 'var(--primary)/10', bgDark: 'var(--primary)/10', textClass: 'text-[var(--primary)]', borderClass: 'border-l-[var(--primary)]' },
  HC_ORDER:     { accent: 'var(--primary)', bgLight: 'var(--primary)/10', bgDark: 'var(--primary)/10', textClass: 'text-[var(--primary)]', borderClass: 'border-l-[var(--primary)]' },
  SC_PETITION:  { accent: 'var(--primary)', bgLight: 'var(--primary)/10', bgDark: 'var(--primary)/10', textClass: 'text-[var(--primary)]', borderClass: 'border-l-[var(--primary)]' },
  SC_ORDER:     { accent: 'var(--primary)', bgLight: 'var(--primary)/10', bgDark: 'var(--primary)/10', textClass: 'text-[var(--primary)]', borderClass: 'border-l-[var(--primary)]' },
  OTHER:        { accent: 'var(--text-secondary)', bgLight: 'var(--surface-hover)', bgDark: 'var(--surface-hover)', textClass: 'text-[var(--text-secondary)]', borderClass: 'border-l-[var(--border-strong)]' },
}

const DEFAULT_COLORS = { accent: 'var(--text-secondary)', bgLight: 'var(--surface-hover)', bgDark: 'var(--surface-hover)', textClass: 'text-[var(--text-secondary)]', borderClass: 'border-l-[var(--border-strong)]' }

function getDocTypeColors(docType?: string) {
  if (!docType) return DEFAULT_COLORS
  return DOC_TYPE_COLORS[docType] || DEFAULT_COLORS
}

export const TimelineGraphNode = memo(({ data, isConnectable }: any) => {
  const { doc, selected } = data
  const isSupporting = doc.document_class === 'supporting'
  const isNeedsReview = doc.status === 'needs_review'
  const isProcessing = doc.status === 'processing' || doc.status === 'uploaded'
  const isFailed = doc.status === 'failed'
  const isPendingPlacement = doc.status === 'pending_placement'
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
            id="timeline-target"
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
              ? `drop-shadow(0 0 1px ${colors.accent}) drop-shadow(0 4px 14px ${colors.accent}55)`
              : 'drop-shadow(0 0 0.75px rgba(255,255,255,0.45)) drop-shadow(0 0 0.5px rgba(0,0,0,0.5)) drop-shadow(0 2px 8px rgba(0,0,0,0.25))',
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
                    color: isFailed ? 'var(--danger)' : colors.accent, lineHeight: 1.1,
                    wordBreak: 'break-all',
                  }}>
                    {isFailed ? 'FAILED' : doc.doc_type?.replace(/_/g, '-') || 'UNKNOWN'}
                  </span>
                  {isNeedsReview && <AlertTriangle size={10} color="var(--warning)" style={{ flexShrink: 0, marginLeft: 4, marginTop: 1 }} />}
                  {isFailed && <XCircle size={10} color="var(--danger)" style={{ flexShrink: 0, marginLeft: 4, marginTop: 1 }} />}
                  {isProcessing && <Loader2 size={10} color="var(--text-muted)" style={{ flexShrink: 0, marginLeft: 4, marginTop: 1, animation: 'spin 1s linear infinite' }} />}
                  {isPendingPlacement && <Clock size={10} color="var(--warning)" style={{ flexShrink: 0, marginLeft: 4, marginTop: 1 }} />}
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
            id="timeline-source"
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


      <HoverCardContent side="right" align="start" className="w-80 p-4 shadow-[var(--shadow-xl)] z-[100] bg-[var(--surface)] border-[var(--border-strong)] rounded-[var(--radius-md)]">
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
                <span className="font-medium text-[var(--danger)]">₹{Number(doc.raw_metadata.extracted_amounts.total_demand).toLocaleString('en-IN')}</span>
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
          <div className="flex items-start gap-2 mb-3 p-2 rounded-[var(--radius-sm)] bg-[var(--warning-muted)] border border-[color-mix(in_srgb,var(--warning)_20%,transparent)] text-[var(--warning)] text-xs">
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
            doc.status === 'processing' || doc.status === 'uploaded' ? 'muted' :
            doc.status === 'needs_review' || doc.status === 'pending_placement' ? 'warning' :
            doc.status === 'failed' ? 'danger' : 'default'
          }
          title={
            doc.status === 'processing' ? 'AI analysis and link resolution in progress' :
            doc.status === 'uploaded' ? 'Queued for processing' :
            doc.status === 'pending_placement' ? 'Waiting for referenced documents to be uploaded before links can be resolved' :
            doc.status === 'failed' ? 'Processing failed — Search-index reprocessing may be available; other scopes require manual recovery' :
            doc.status === 'needs_review' ? 'Requires manual review before placement' :
            doc.status === 'placed' ? 'Fully processed and linked' :
            doc.status === 'analyzed' ? 'Metadata extracted, awaiting link resolution' :
            ''
          }
          >
            {doc.status === 'pending_placement' ? 'pending links' : doc.status.replace('_', ' ')}
          </Badge>
        </div>
      </HoverCardContent>
    </HoverCard>
  )
})
