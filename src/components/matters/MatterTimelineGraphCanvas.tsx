'use client'

import { useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import {
  Background,
  BackgroundVariant,
  MarkerType,
  ReactFlow,
  useEdgesState,
  useNodesState,
  type Edge,
  type ReactFlowInstance,
} from '@xyflow/react'
import '@xyflow/react/dist/style.css'

import { Button } from '@/components/ui/button'
import type { MatterTimelineGraphLayout } from '@/lib/matters/matter-timeline-graph-layout'
import {
  buildMatterDocumentSelectionHref,
  buildMatterRelationshipSelectionHref,
} from '@/lib/matters/workspace-route'
import { MatterTimelineFocusCommit } from './MatterTimelineFocusBridge'
import { MatterTimelineGraphNode, type MatterTimelineFlowNode } from './MatterTimelineGraphNode'
import { MatterTimelineFilters } from './MatterTimelineFilters'
import { MatterRelationshipAuthoring } from './MatterRelationshipAuthoring'
import { canAddTimelineRelationship, type RelationshipAuthoringContext } from '@/lib/matters/relationship-authoring'
import type { TimelineRelationshipReviewCandidate } from '@/lib/review/relationship-suggestion'

const nodeTypes = { matterTimelineDocument: MatterTimelineGraphNode }

type TimelineFlowEdgeData = Record<string, unknown> & {
  canonicalSourceDocumentId?: string
  relationshipLabels: string[]
}

type MatterTimelineFlowEdge = Edge<TimelineFlowEdgeData>

export type MatterTimelineGraphCanvasProps = {
  authoringContext?: RelationshipAuthoringContext | null
  matterId: string
  layout: MatterTimelineGraphLayout
  selectedDocumentId: string | null
  queryEntries: Array<[string, string]>
  chronologyHref: string
  inspector: ReactNode
  filteredCountLabel: string
  filters: string[]
  relationshipReviewCandidate?: TimelineRelationshipReviewCandidate | null
}

function createNodes(
  layout: MatterTimelineGraphLayout,
  matterId: string,
  entries: Array<[string, string]>,
  selectedDocumentId: string | null,
  reviewCandidate?: TimelineRelationshipReviewCandidate | null,
): MatterTimelineFlowNode[] {
  return layout.nodes.map((node) => ({
    id: node.id,
    type: 'matterTimelineDocument',
    position: node.position,
    width: node.width,
    height: node.height,
    style: {
      width: node.width,
      height: node.height,
      opacity: reviewCandidate && node.id !== reviewCandidate.sourceDocumentId && node.id !== reviewCandidate.targetDocumentId ? 0.32 : 1,
    },
    data: {
      layout: node,
      href: buildMatterDocumentSelectionHref(matterId, entries, node.id),
      selected: selectedDocumentId === node.id,
    },
  }))
}

function createEdges(layout: MatterTimelineGraphLayout, zoom: number, reviewCandidate?: TimelineRelationshipReviewCandidate | null): MatterTimelineFlowEdge[] {
  const effectiveEdges: MatterTimelineFlowEdge[] = layout.edges.map((edge) => ({
    id: edge.id,
    source: edge.displayFromDocumentId,
    target: edge.displayToDocumentId,
    type: 'smoothstep',
    label: zoom >= 0.65 ? edge.label : undefined,
    markerEnd: { type: MarkerType.ArrowClosed, color: 'var(--text-muted)', width: 18, height: 18 },
    style: { stroke: 'var(--text-muted)', strokeWidth: 1.5, opacity: reviewCandidate ? 0.22 : 1 } as CSSProperties,
    labelStyle: { fill: 'var(--text-secondary)', fontSize: 11, fontWeight: 500 },
    labelBgStyle: { fill: 'var(--surface)', stroke: 'var(--border)' },
    labelBgPadding: [6, 4],
    labelBgBorderRadius: 6,
    data: {
      canonicalSourceDocumentId: edge.canonicalSourceDocumentId,
      relationshipLabels: edge.relationships.map((relationship) => (
        `${relationship.canonicalSourceTitle} ${relationship.canonicalPhrase} ${relationship.canonicalTargetTitle}`
      )),
    },
  }))
  if (!reviewCandidate || !layout.nodes.some((node) => node.id === reviewCandidate.sourceDocumentId) || !layout.nodes.some((node) => node.id === reviewCandidate.targetDocumentId)) return effectiveEdges
  return [...effectiveEdges, {
    id: `review-candidate:${reviewCandidate.sourceDocumentId}:${reviewCandidate.targetDocumentId}`,
    source: reviewCandidate.sourceDocumentId,
    target: reviewCandidate.targetDocumentId,
    type: 'smoothstep',
    label: 'Candidate · refers to',
    markerEnd: { type: MarkerType.ArrowClosed, color: 'var(--warning)', width: 18, height: 18 },
    style: { stroke: 'var(--warning)', strokeWidth: 2, strokeDasharray: '7 5' } as CSSProperties,
    labelStyle: { fill: 'var(--text-primary)', fontSize: 11, fontWeight: 600 },
    labelBgStyle: { fill: 'var(--surface)', stroke: 'var(--warning)' },
    labelBgPadding: [6, 4],
    labelBgBorderRadius: 6,
    data: { relationshipLabels: ['Non-authoritative exact-reference candidate'] },
  }]
}

export default function MatterTimelineGraphCanvas({
  matterId,
  layout,
  selectedDocumentId,
  queryEntries,
  chronologyHref,
  inspector,
  filteredCountLabel,
  filters,
  authoringContext,
  relationshipReviewCandidate,
}: MatterTimelineGraphCanvasProps) {
  const router = useRouter()
  const viewportRef = useRef<HTMLDivElement>(null)
  const instanceRef = useRef<ReactFlowInstance<MatterTimelineFlowNode, MatterTimelineFlowEdge> | null>(null)
  const topologyRef = useRef('')
  const [zoom, setZoom] = useState(1)
  const [hasDragged, setHasDragged] = useState(false)
  const [authoring, setAuthoring] = useState<{ sourceId: string; targetId: string } | null>(null)
  const [authoringMessage, setAuthoringMessage] = useState('')
  const addButton = useRef<HTMLButtonElement>(null)
  const cancelAddButton = useRef<HTMLButtonElement>(null)
  const authoringActive = Boolean(authoring)
  useEffect(() => { if (authoringActive) cancelAddButton.current?.focus() }, [authoringActive])
  function finishAuthoring() { setAuthoring(null); setAuthoringMessage(''); requestAnimationFrame(() => addButton.current?.focus()) }
  const projectedNodes = useMemo(
    () => createNodes(layout, matterId, queryEntries, selectedDocumentId, relationshipReviewCandidate),
    [layout, matterId, queryEntries, selectedDocumentId, relationshipReviewCandidate],
  )
  const projectedEdges = useMemo(() => createEdges(layout, zoom, relationshipReviewCandidate), [layout, zoom, relationshipReviewCandidate])
  const [nodes, setNodes, onNodesChange] = useNodesState<MatterTimelineFlowNode>(projectedNodes)
  const [edges, setEdges, onEdgesChange] = useEdgesState<MatterTimelineFlowEdge>(projectedEdges)
  const topology = `${layout.nodes.map((node) => node.id).join('|')}::${layout.edges.map((edge) => edge.id).join('|')}`

  useEffect(() => {
    const topologyChanged = topologyRef.current !== topology
    topologyRef.current = topology
    setNodes((current) => projectedNodes.map((projected) => {
      const existing = current.find((node) => node.id === projected.id)
      return topologyChanged && existing
        ? { ...projected, position: existing.position }
        : topologyChanged ? projected : { ...existing, ...projected, position: existing?.position ?? projected.position }
    }))
  }, [projectedNodes, setNodes, topology])

  useEffect(() => {
    setEdges(projectedEdges)
  }, [projectedEdges, setEdges])

  useEffect(() => {
    const instance = instanceRef.current
    const viewport = viewportRef.current
    if (!instance || !viewport || !selectedDocumentId) return
    const selected = instance.getNode(selectedDocumentId)
    if (!selected) return
    const center = instance.flowToScreenPosition({
      x: selected.position.x + (selected.width ?? 184) / 2,
      y: selected.position.y + (selected.height ?? 120) / 2,
    })
    const bounds = viewport.getBoundingClientRect()
    const obscured = center.x < bounds.left + 100 || center.x > bounds.right - 100
      || center.y < bounds.top + 76 || center.y > bounds.bottom - 76
    if (obscured) instance.setCenter(
      selected.position.x + (selected.width ?? 184) / 2,
      selected.position.y + (selected.height ?? 120) / 2,
      { zoom: instance.getZoom(), duration: 0 },
    )
  }, [selectedDocumentId, nodes])

  const unlinkedCount = layout.nodes.filter((node) => node.unlinked).length

  return (
    <div className="flex h-full min-h-0 flex-col gap-2 pt-2 lg:pt-3" onKeyDown={(event) => { if (authoring && !event.defaultPrevented && event.key === 'Escape') { event.preventDefault(); finishAuthoring() } }}>
      <MatterTimelineFocusCommit selectedDocumentId={selectedDocumentId} matterId={matterId} snapshot={topology} />
      <div className="flex min-h-11 shrink-0 flex-wrap items-center justify-between gap-2 border-b border-[var(--border)] bg-[var(--surface)] px-3 py-2">
        <div>
          <h2 className="text-sm font-semibold text-[var(--text-primary)]">Procedural timeline</h2>
          <p className="text-xs text-[var(--text-muted)]">{filteredCountLabel}</p>
        </div>
        <div className="flex flex-wrap items-center justify-end gap-2">
          {relationshipReviewCandidate ? <p className="text-xs text-[var(--text-secondary)]">Dashed edge is a candidate only · no relationship is effective</p> : null}
          {!relationshipReviewCandidate && canAddTimelineRelationship(authoringContext) && <Button ref={addButton} disabled={Boolean(authoring)} onClick={() => setAuthoring({ sourceId: '', targetId: '' })}>Add relationship</Button>}
          {authoringContext && authoring && <Button ref={cancelAddButton} variant="outline" onClick={finishAuthoring}>Cancel adding relationship</Button>}
          {authoringContext && authoring?.targetId && <MatterRelationshipAuthoring key={`${authoring.sourceId}:${authoring.targetId}`} matterId={matterId} context={authoringContext} initialSourceId={authoring.sourceId} initialTargetId={authoring.targetId} initiallyOpen onFinish={finishAuthoring} />}
          <MatterTimelineFilters matterId={matterId} entries={queryEntries} filters={filters} />
          <Button type="button" variant="secondary" className="min-h-11" onClick={() => instanceRef.current?.fitView({ padding: 0.18, duration: 0 })}>Fit timeline</Button>
          <Button type="button" variant="ghost" className="min-h-11" onClick={() => instanceRef.current?.zoomIn({ duration: 0 })}>Zoom in</Button>
          <Button type="button" variant="ghost" className="min-h-11" onClick={() => instanceRef.current?.zoomOut({ duration: 0 })}>Zoom out</Button>
          {hasDragged ? <Button type="button" variant="ghost" className="min-h-11" onClick={() => { setNodes(projectedNodes); setHasDragged(false) }}>Reset layout</Button> : null}
          {!relationshipReviewCandidate && <details className="relative">
            <summary className="flex min-h-11 cursor-pointer list-none items-center rounded-[var(--radius-sm)] px-3 text-sm font-medium text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">Relationship list ({layout.edges.length})</summary>
            <div className="custom-scrollbar absolute right-0 z-30 mt-1 max-h-72 w-[min(24rem,calc(100vw-2rem))] overflow-y-auto rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] p-2 shadow-[var(--shadow-md)]">
              {layout.edges.length === 0 ? <p className="p-2 text-sm text-[var(--text-secondary)]">No visible relationships connect these proceedings.</p> : (
                <ol aria-label="Timeline relationships" className="space-y-1">
                  {layout.edges.map((edge) => (
                    <li key={edge.id}>
                      <Link
                        href={buildMatterRelationshipSelectionHref(matterId, queryEntries, edge.canonicalSourceDocumentId)}
                        scroll={false}
                        prefetch={false}
                        className="block min-h-11 rounded-[var(--radius-sm)] p-2 text-sm text-[var(--text-primary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
                      >
                        <span className="font-medium">{edge.label}</span>
                        <span className="mt-1 block text-xs text-[var(--text-secondary)]">{edge.relationships.map((relationship) => `${relationship.canonicalSourceTitle} ${relationship.canonicalPhrase} ${relationship.canonicalTargetTitle}`).join('; ')}</span>
                      </Link>
                    </li>
                  ))}
                </ol>
              )}
            </div>
          </details>}
          <Link href={chronologyHref} scroll={false} prefetch={false} className="inline-flex min-h-11 items-center rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 text-sm font-medium text-[var(--text-primary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">Chronology</Link>
        </div>
      </div>
      <div className="min-h-0 flex-1 gap-3 lg:flex">
        <div ref={viewportRef} onKeyDown={(event) => { if (authoring && event.key === 'Escape') { event.preventDefault(); finishAuthoring() } }} onClickCapture={(event) => {
          if (!authoring || !authoringContext) return
          const id = (event.target as HTMLElement).closest('[data-authoring-document-id]')?.getAttribute('data-authoring-document-id')
          if (!id) return
          event.preventDefault(); event.stopPropagation()
          if (!authoringContext.documents.some((document) => document.id === id)) { setAuthoringMessage('This proceeding is no longer available.'); return }
          if (authoring.sourceId === id) { setAuthoringMessage('Choose a different target document.'); return }
          setAuthoringMessage('')
          setAuthoring(authoring.sourceId ? { ...authoring, targetId: id } : { sourceId: id, targetId: '' })
        }} className="relative min-h-0 flex-1 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]" aria-label="Procedural timeline graph">
          {authoring && <p role="status" className="absolute left-2 right-2 top-2 z-10 border border-[var(--border)] bg-[var(--surface)] p-3 text-sm text-[var(--text-primary)]">{authoringMessage || (authoring.sourceId ? '2. Choose the target document acted on. Choose a different proceeding.' : '1. Choose the source document that performs the relationship action.')}</p>}
          <ReactFlow<MatterTimelineFlowNode, MatterTimelineFlowEdge>
            nodes={nodes}
            edges={edges}
            nodeTypes={nodeTypes}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onInit={(instance) => { instanceRef.current = instance }}
            onMove={(_, viewport) => setZoom(viewport.zoom)}
            onNodeDragStop={() => setHasDragged(true)}
            onEdgeClick={(_, edge) => {
              if (edge.data?.canonicalSourceDocumentId) router.push(
                buildMatterRelationshipSelectionHref(matterId, queryEntries, edge.data.canonicalSourceDocumentId),
                { scroll: false },
              )
            }}
            nodesConnectable={false}
            deleteKeyCode={null}
            edgesFocusable={false}
            nodesFocusable={false}
            elementsSelectable
            onlyRenderVisibleElements
            minZoom={0.25}
            maxZoom={1.8}
            defaultViewport={{ x: 32, y: 48, zoom: 1 }}
            fitView={false}
            attributionPosition="bottom-right"
          >
            <Background variant={BackgroundVariant.Dots} gap={24} size={1} color="var(--border-subtle)" />
          </ReactFlow>
          {unlinkedCount > 0 ? <p className="pointer-events-none absolute bottom-3 left-3 rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1 text-xs text-[var(--text-secondary)]">Unlinked lane · {unlinkedCount} proceeding{unlinkedCount === 1 ? '' : 's'}</p> : null}
        </div>
        {inspector}
      </div>
    </div>
  )
}
