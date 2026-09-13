'use client'

import { Handle, Position, type Node, type NodeProps } from '@xyflow/react'

import { Badge } from '@/components/ui/badge'
import type { MatterTimelineGraphNodeLayout } from '@/lib/matters/matter-timeline-graph-layout'
import { MatterTimelineRowLink } from './MatterTimelineFocusBridge'

export type MatterTimelineGraphNodeData = Record<string, unknown> & {
  layout: MatterTimelineGraphNodeLayout
  href: string
  selected: boolean
}

export type MatterTimelineFlowNode = Node<MatterTimelineGraphNodeData, 'matterTimelineDocument'>

function readableDate(value: string | null) {
  return value
    ? new Intl.DateTimeFormat('en-GB', { dateStyle: 'medium' }).format(new Date(`${value}T00:00:00Z`))
    : 'Date unavailable'
}

function attention(value: MatterTimelineGraphNodeLayout['document']['attentionState']) {
  if (value === 'processing') return 'Processing'
  if (value === 'review') return 'Needs review'
  if (value === 'failed') return 'Processing failed'
  return 'No attention required'
}

function unavailableSource(value: MatterTimelineGraphNodeLayout['document']['contentAvailability']) {
  if (value === 'metadata_only') return 'PDF not attached'
  if (value === 'source_unreadable') return 'Source unreadable'
  return null
}

export function matterTimelineNodeAccessibleName(layout: MatterTimelineGraphNodeLayout) {
  const item = layout.document
  return [
    item.title || 'Untitled proceeding',
    item.documentType || 'Document type unavailable',
    item.referenceNumber || 'Reference unavailable',
    readableDate(item.effectiveDate),
    item.direction ? `${item.direction} document` : 'Direction unavailable',
    attention(item.attentionState),
    unavailableSource(item.contentAvailability),
    layout.unlinked ? 'Unlinked proceeding' : null,
  ].filter(Boolean).join(', ')
}

export function MatterTimelineGraphNode({ data }: NodeProps<MatterTimelineFlowNode>) {
  const item = data.layout.document
  const selected = data.selected
  const statusClass = item.attentionState === 'failed' || item.contentAvailability === 'source_unreadable'
    ? 'border-[var(--danger)]'
    : item.attentionState === 'review'
      ? 'border-[var(--warning)]'
      : selected ? 'border-[var(--primary)]' : 'border-[var(--border-strong)]'

  return (
    <div
      className={`relative overflow-hidden rounded-[var(--radius-md)] border bg-[var(--surface)] shadow-[var(--shadow-xs)] ${statusClass}`}
      style={{ width: data.layout.width, height: data.layout.height }}
      data-unlinked={data.layout.unlinked || undefined}
      data-authoring-document-id={item.id}
    >
      <Handle type="target" position={Position.Left} isConnectable={false} className="!h-px !w-px !border-0 !bg-transparent !opacity-0" />
      <MatterTimelineRowLink
        documentId={item.id}
        href={data.href}
        ariaLabel={matterTimelineNodeAccessibleName(data.layout)}
        selected={selected}
        className="block h-full rounded-[var(--radius-md)] p-3 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]"
      >
        <span className="flex h-6 min-w-0 items-start justify-between gap-2">
          <span className="truncate font-mono text-[11px] font-medium text-[var(--text-secondary)]">
            {item.documentType || item.referenceNumber || 'Type unavailable'}
          </span>
          {item.direction ? <Badge variant={item.direction} className="min-h-5 px-1.5 text-[10px] capitalize">{item.direction}</Badge> : null}
        </span>
        <span className="line-clamp-2 min-h-9 text-sm font-semibold leading-[18px] text-[var(--text-primary)]">
          {item.title || 'Untitled proceeding'}
        </span>
        <span className="mt-1 flex items-center justify-between gap-2 text-[11px] text-[var(--text-muted)]">
          <span className="truncate font-mono">{readableDate(item.effectiveDate)}</span>
          {data.layout.unlinked ? <span className="shrink-0">Unlinked</span> : null}
        </span>
        <span className="mt-1 block truncate text-[11px] text-[var(--text-secondary)]">
          {unavailableSource(item.contentAvailability) ? `${unavailableSource(item.contentAvailability)} · ` : ''}Effect unavailable
        </span>
      </MatterTimelineRowLink>
      <Handle type="source" position={Position.Right} isConnectable={false} className="!h-px !w-px !border-0 !bg-transparent !opacity-0" />
    </div>
  )
}
