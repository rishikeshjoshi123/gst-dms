'use client'

import { useState, useMemo, useCallback, useEffect, useRef } from 'react'
import { toast } from 'sonner'
import { Clock, RefreshCw, EyeOff, Eye, HelpCircle } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { autoLinkUnlinkedDocuments } from '@/lib/actions/matter'
import { useTransition } from 'react'
import { Loader2 } from 'lucide-react'
import {
  ReactFlow,
  MiniMap,
  Controls,
  Background,
  useNodesState,
  useEdgesState,
  MarkerType,
  Connection,
  BackgroundVariant,
  Edge,
  Node,
} from '@xyflow/react'
import '@xyflow/react/dist/style.css'
import dagre from 'dagre'
import { TimelineGraphNode } from './TimelineGraphNode'
import { LinkCreationDialog } from './LinkCreationDialog'
import { LinkDeletionDialog } from './LinkDeletionDialog'
import { TimelineHelpDialog } from './TimelineHelpDialog'
import type { DocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'
import type { TimelineDocument } from './TimelineListFallback'

type TimelineGraphDocument = TimelineDocument & {
  matter_id?: string | null
}

const nodeTypes = {
  document: TimelineGraphNode,
}

// React Flow needs dimensions on its node wrapper to calculate handle
// positions and render edges. The custom card itself is 148px wide.
const nodeWidth = 148
const nodeHeight = 100

const getLayoutedElements = (nodes: any[], edges: any[], direction = 'TB') => {
  const dagreGraph = new dagre.graphlib.Graph()
  dagreGraph.setDefaultEdgeLabel(() => ({}))
  const isHorizontal = direction === 'LR'
  dagreGraph.setGraph({ rankdir: direction, ranksep: 100, nodesep: 50 })

  nodes.forEach((node) => {
    dagreGraph.setNode(node.id, { width: nodeWidth, height: nodeHeight })
  })

  edges.forEach((edge) => {
    dagreGraph.setEdge(edge.source, edge.target)
  })

  dagre.layout(dagreGraph)

  const newNodes = nodes.map((node) => {
    const nodeWithPosition = dagreGraph.node(node.id)
    return {
      ...node,
      targetPosition: isHorizontal ? 'left' : 'top',
      sourcePosition: isHorizontal ? 'right' : 'bottom',
      position: {
        x: nodeWithPosition.x - nodeWidth / 2,
        y: nodeWithPosition.y - nodeHeight / 2,
      },
    }
  })

  return { nodes: newNodes, edges }
}

/** Build a stable edge object from a DB link record */
function buildEdgeFromLink(l: any) {
  const isManual = l.match_method === 'manual'
  const color = isManual ? '#2563eb' : (l.status === 'pending' ? '#f59e0b' : '#94a3b8')
  return {
    id: l.id,
    source: l.to_doc_id,
    target: l.from_doc_id,
    sourceHandle: 'timeline-source',
    targetHandle: 'timeline-target',
    label: l.link_type?.replace('_', ' ').toUpperCase() || 'LINKS TO',
    type: 'smoothstep',
    animated: l.status === 'pending',
    style: {
      stroke: color,
      strokeWidth: isManual ? 3 : 2,
      strokeDasharray: (isManual || l.status === 'pending') ? 'none' : '5, 5',
    },
    labelStyle: { fill: 'var(--text-secondary)', fontWeight: 600, fontSize: 10 },
    labelBgStyle: { fill: 'var(--surface)', fillOpacity: 0.95, stroke: 'var(--border)', strokeWidth: 1 },
    labelBgPadding: [4, 2] as [number, number],
    labelBgBorderRadius: 4,
    markerEnd: {
      type: MarkerType.ArrowClosed,
      width: 15,
      height: 15,
      color,
    },
  }
}

/** Build a temporary "optimistic pending" edge while awaiting server response */
function buildOptimisticEdge(connection: Connection, tempId: string): Edge {
  return {
    id: tempId,
    source: connection.source!,
    target: connection.target!,
    sourceHandle: connection.sourceHandle ?? 'timeline-source',
    targetHandle: connection.targetHandle ?? 'timeline-target',
    label: 'PENDING...',
    type: 'smoothstep',
    animated: true,
    style: {
      stroke: '#94a3b8',
      strokeWidth: 2,
      strokeDasharray: '6, 4',
    },
    labelStyle: { fill: '#94a3b8', fontWeight: 600, fontSize: 9 },
    labelBgStyle: { fill: 'var(--surface)', fillOpacity: 0.9, stroke: '#94a3b8', strokeWidth: 1 },
    labelBgPadding: [4, 2] as [number, number],
    labelBgBorderRadius: 4,
    markerEnd: {
      type: MarkerType.ArrowClosed,
      width: 15,
      height: 15,
      color: '#94a3b8',
    },
  } as Edge
}

export function TimelineGraph({ 
  documents, 
  links,
  selectedDocId,
  onSelectDoc,
  inspectorMetadataByDocumentId = {},
}: { 
  documents: TimelineGraphDocument[],
  links: any[],
  selectedDocId?: string | null,
  onSelectDoc?: (id: string) => void,
  inspectorMetadataByDocumentId?: Record<string, DocumentInspectorMetadata>
}) {
  const [isPending, startTransition] = useTransition()
  const [showSupporting, setShowSupporting] = useState(true)
  
  // Link Creation State
  const [linkDialogState, setLinkDialogState] = useState<{
    isOpen: boolean;
    sourceDoc: TimelineGraphDocument | null;
    targetDoc: TimelineGraphDocument | null;
    pendingEdgeId: string | null;
    connection: Connection | null;
  }>({ isOpen: false, sourceDoc: null, targetDoc: null, pendingEdgeId: null, connection: null })

  // Link Deletion State
  const [deleteDialogState, setDeleteDialogState] = useState<{
    isOpen: boolean;
    linkId: string | null;
    edgeId: string | null;
    sourceDoc: TimelineGraphDocument | null;
    targetDoc: TimelineGraphDocument | null;
    linkType?: string | null;
  }>({ isOpen: false, linkId: null, edgeId: null, sourceDoc: null, targetDoc: null, linkType: null })
  
  const matterId = documents.length > 0 ? documents[0].matter_id : null

  // Track user-dragged node positions so layout resets don't snap them back
  const draggedPositions = useRef<Record<string, { x: number; y: number }>>({})
  // Track which node/edge IDs existed in the previous render to detect additions/removals
  const prevNodeIds = useRef<Set<string>>(new Set())
  const prevEdgeIds = useRef<Set<string>>(new Set())

  const handleReevaluate = () => {
    if (!matterId) return
    const toastId = toast.loading('Re-evaluating matter links...')
    startTransition(async () => {
      try {
        const res = await autoLinkUnlinkedDocuments(matterId)
        if (res && 'error' in res) {
          toast.error(res.error, { id: toastId })
        } else if (res && 'success' in res) {
          toast.success(`Processed ${res.count} documents successfully!`, {
            id: toastId,
            description: `If documents are still unlinked, they may be missing required metadata. Please ensure their 'Document Type' and 'Reference Number' are correct. (e.g., a DRC-07 needs an existing 'OIO' document to link to).`
          })
        }
      } catch (err: any) {
        toast.error(err.message || 'Failed to re-evaluate links', { id: toastId })
      }
    })
  }

  // Filter documents based on toggle
  const visibleDocuments = useMemo(() => {
    if (showSupporting) return documents
    return documents.filter(d => d.document_class !== 'supporting')
  }, [documents, showSupporting])

  const visibleDocIds = useMemo(() => new Set(visibleDocuments.map(d => d.id)), [visibleDocuments])

  // Build nodes and edges from server data
  const { nodes: initialNodes, edges: initialEdges } = useMemo(() => {
    const nodes = visibleDocuments.map(doc => ({
      id: doc.id,
      type: 'document',
      data: { 
        doc, 
        selected: selectedDocId === doc.id,
        effectiveMetadata: inspectorMetadataByDocumentId[doc.id],
      },
      position: { x: 0, y: 0 }, // Dagre will override this
      style: { width: nodeWidth, height: nodeHeight },
    }))

    const edges = links
      .filter(l => visibleDocIds.has(l.from_doc_id) && visibleDocIds.has(l.to_doc_id))
      .map(buildEdgeFromLink)

    return getLayoutedElements(nodes, edges, 'TB')
  }, [visibleDocuments, visibleDocIds, links, selectedDocId, inspectorMetadataByDocumentId])

  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes)
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges)

  useEffect(() => {
    const currentNodeIds = new Set(initialNodes.map(n => n.id))
    const currentEdgeIds = new Set(initialEdges.map(e => e.id))
    
    const hadAddOrRemove =
      currentNodeIds.size !== prevNodeIds.current.size ||
      initialNodes.some(n => !prevNodeIds.current.has(n.id)) ||
      currentEdgeIds.size !== prevEdgeIds.current.size ||
      initialEdges.some(e => !prevEdgeIds.current.has(e.id))

    prevNodeIds.current = currentNodeIds
    prevEdgeIds.current = currentEdgeIds

    if (hadAddOrRemove) {
      // Full re-layout needed (node topology changed) — but merge in any dragged positions and preserve React Flow state
      setNodes(nds => initialNodes.map(n => {
        const existing = nds.find(nd => nd.id === n.id)
        return {
          ...existing, // Preserves React Flow internal properties like `measured` (fixes invisibility bug)
          ...n,
          data: { ...existing?.data, ...n.data },
          position: draggedPositions.current[n.id] ?? n.position,
        }
      }))
    } else {
      // Node topology didn't change, just update data (e.g. selected state, status) without resetting positions
      setNodes(nds => nds.map(n => {
        const fresh = initialNodes.find(fn => fn.id === n.id)
        if (fresh) {
          return {
            ...n,
            data: { ...n.data, ...fresh.data }
          }
        }
        return n
      }))
    }

    // Always sync edges — preserve any in-flight optimistic edges
    setEdges(prev => {
      const optimisticEdges = prev.filter(e => e.id.startsWith('optimistic_'))
      return [...initialEdges, ...optimisticEdges]
    })
  }, [initialNodes, initialEdges, setNodes, setEdges])

  /** Persist drag positions so re-layouts don't snap nodes back */
  const onNodeDragStop = useCallback((_: MouseEvent | TouchEvent, node: Node) => {
    draggedPositions.current[node.id] = node.position
  }, [])


  const onNodeClick = useCallback((event: React.MouseEvent, node: any) => {
    if (onSelectDoc) {
      onSelectDoc(node.id)
    }
  }, [onSelectDoc])

  const onConnect = useCallback((connection: Connection) => {
    // Check if link already exists between these 2 nodes
    const existingEdge = edges.find(e => 
      (e.source === connection.source && e.target === connection.target) || 
      (e.source === connection.target && e.target === connection.source)
    )

    const sourceDoc = visibleDocuments.find(d => d.id === connection.source)
    const targetDoc = visibleDocuments.find(d => d.id === connection.target)

    if (existingEdge) {
      if (sourceDoc && targetDoc) {
        setDeleteDialogState({
          isOpen: true,
          linkId: existingEdge.id.startsWith('optimistic_') ? null : existingEdge.id,
          edgeId: existingEdge.id,
          sourceDoc,
          targetDoc,
          linkType: (existingEdge as any).label
        })
      }
      return
    }

    if (sourceDoc && targetDoc) {
      // Add optimistic pending edge immediately — user sees feedback right away
      const tempId = `optimistic_${Date.now()}`
      const optimisticEdge = buildOptimisticEdge(connection, tempId)
      setEdges(prev => [...prev, optimisticEdge])

      setLinkDialogState({
        isOpen: true,
        sourceDoc,
        targetDoc,
        pendingEdgeId: tempId,
        connection,
      })
    }
  }, [visibleDocuments, edges, setEdges])

  /** User cancelled link creation — remove the optimistic edge */
  const handleLinkDialogClose = useCallback(() => {
    const { pendingEdgeId } = linkDialogState
    if (pendingEdgeId) {
      setEdges(prev => prev.filter(e => e.id !== pendingEdgeId))
    }
    setLinkDialogState({ isOpen: false, sourceDoc: null, targetDoc: null, pendingEdgeId: null, connection: null })
  }, [linkDialogState, setEdges])

  /** Server confirmed creation — replace optimistic edge with confirmed one */
  const handleLinkCreated = useCallback((realLink: any) => {
    const { pendingEdgeId } = linkDialogState
    if (pendingEdgeId && realLink) {
      setEdges(prev => [
        ...prev.filter(e => e.id !== pendingEdgeId),
        buildEdgeFromLink(realLink),
      ])
    } else if (pendingEdgeId) {
      // No real link data yet — remove optimistic; revalidatePath / realtime will re-populate
      setEdges(prev => prev.filter(e => e.id !== pendingEdgeId))
    }
    setLinkDialogState({ isOpen: false, sourceDoc: null, targetDoc: null, pendingEdgeId: null, connection: null })
  }, [linkDialogState, setEdges])

  /** Optimistic delete — remove edge immediately before server responds */
  const handleOptimisticDelete = useCallback((edgeId: string) => {
    setEdges(prev => prev.filter(e => e.id !== edgeId))
  }, [setEdges])

  const handleDeleteDialogClose = useCallback(() => {
    setDeleteDialogState({ isOpen: false, linkId: null, edgeId: null, sourceDoc: null, targetDoc: null, linkType: null })
  }, [])

  const [isHelpOpen, setIsHelpOpen] = useState(false)

  const onEdgeClick = useCallback((event: React.MouseEvent) => {
    event.stopPropagation()
    // Clicking on an edge line does nothing as requested. Deletion dialog appears ONLY when drawing an edge over an existing link.
  }, [])

  return (
    <div className="flex flex-col h-full border border-[var(--border)] rounded-lg overflow-hidden bg-[var(--bg)] relative transition-colors">
      {/* Graph Toolbar */}
      <div className="p-4 bg-[var(--surface)] border-b border-[var(--border)] flex flex-wrap items-center justify-between gap-4 shrink-0 transition-colors">
        <div className="flex items-center gap-3">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setShowSupporting(!showSupporting)}
            className="h-8 text-xs font-semibold bg-[var(--surface)] text-[var(--text-primary)] border-[var(--border-strong)] shadow-xs hover:border-[var(--primary)]"
          >
            {showSupporting ? <EyeOff size={14} className="mr-1.5 text-[var(--text-muted)]" /> : <Eye size={14} className="mr-1.5 text-[var(--primary)]" />}
            {showSupporting ? 'Hide Supporting' : 'Show Supporting'}
          </Button>
          <span className="text-[12px] font-medium text-[var(--text-muted)]">
            Showing {visibleDocuments.length} of {documents.length} documents
          </span>
        </div>

        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={handleReevaluate}
            disabled={isPending}
            className="h-8 text-xs font-semibold bg-[var(--surface)] text-[var(--text-primary)] border-[var(--border-strong)] shadow-xs hover:border-[var(--primary)]"
          >
            <RefreshCw size={14} className={`mr-1.5 text-[var(--warning)] ${isPending ? 'animate-spin' : ''}`} />
            Re-evaluate Links
          </Button>

          <Button 
            variant="outline" 
            size="sm" 
            onClick={() => setIsHelpOpen(true)}
            className="h-8 text-xs font-semibold bg-[var(--surface)] text-[var(--text-primary)] border-[var(--border-strong)] shadow-xs hover:border-[var(--primary)]"
          >
            <HelpCircle size={14} className="mr-1.5 text-[var(--primary)]" />
            Help
          </Button>
        </div>
      </div>

      <div className="flex-1 w-full relative">
        <ReactFlow
          nodes={nodes}
          edges={edges}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onNodeClick={onNodeClick}
          onNodeDragStop={onNodeDragStop}
          onEdgeClick={onEdgeClick}
          onConnect={onConnect}
          nodeTypes={nodeTypes}
          fitView
          fitViewOptions={{ padding: 0.2 }}
          minZoom={0.1}
          proOptions={{ hideAttribution: true }}
        >
          <Background color="var(--border-strong)" gap={24} size={2} variant={BackgroundVariant.Dots} />
          <Controls className="bg-[var(--surface)] border-[var(--border)] shadow-sm rounded-md overflow-hidden" />
          <MiniMap 
            nodeColor={(node) => {
              const data = node.data as any;
              if (data?.doc?.status === 'needs_review') return '#f59e0b'
              if (data?.doc?.document_class === 'supporting') return 'var(--border-strong)'
              return 'var(--primary)'
            }}
            nodeStrokeColor={(node) => {
              const data = node.data as any;
              if (data?.doc?.status === 'needs_review') return '#d97706'
              if (data?.doc?.document_class === 'supporting') return '#78716c'
              return '#1d4ed8'
            }}
            nodeStrokeWidth={2}
            maskColor="rgba(0,0,0,0.08)"
            className="bg-[var(--surface)] border-[var(--border)] shadow-sm rounded-md"
            style={{ height: 140 }}
          />
        </ReactFlow>
      </div>
      
      <LinkCreationDialog
        isOpen={linkDialogState.isOpen}
        sourceDoc={linkDialogState.sourceDoc}
        targetDoc={linkDialogState.targetDoc}
        connection={linkDialogState.connection}
        parentEffectiveMetadata={linkDialogState.sourceDoc ? inspectorMetadataByDocumentId[linkDialogState.sourceDoc.id] : undefined}
        childEffectiveMetadata={linkDialogState.targetDoc ? inspectorMetadataByDocumentId[linkDialogState.targetDoc.id] : undefined}
        onClose={handleLinkDialogClose}
        onSuccess={handleLinkCreated}
      />

      <LinkDeletionDialog
        isOpen={deleteDialogState.isOpen}
        linkId={deleteDialogState.linkId}
        edgeId={deleteDialogState.edgeId}
        sourceDoc={deleteDialogState.sourceDoc}
        targetDoc={deleteDialogState.targetDoc}
        linkType={deleteDialogState.linkType}
        sourceEffectiveMetadata={deleteDialogState.sourceDoc ? inspectorMetadataByDocumentId[deleteDialogState.sourceDoc.id] : undefined}
        targetEffectiveMetadata={deleteDialogState.targetDoc ? inspectorMetadataByDocumentId[deleteDialogState.targetDoc.id] : undefined}
        onClose={handleDeleteDialogClose}
        onOptimisticDelete={handleOptimisticDelete}
      />

      <TimelineHelpDialog
        isOpen={isHelpOpen}
        onClose={() => setIsHelpOpen(false)}
      />
    </div>
  )
}
