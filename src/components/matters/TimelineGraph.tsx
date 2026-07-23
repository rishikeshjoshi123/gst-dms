'use client'

import { useState, useMemo, useCallback, useEffect } from 'react'
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
  addEdge,
  BackgroundVariant
} from '@xyflow/react'
import '@xyflow/react/dist/style.css'
import dagre from 'dagre'
import { TimelineGraphNode } from './TimelineGraphNode'
import { LinkCreationDialog } from './LinkCreationDialog'
import { LinkDeletionDialog } from './LinkDeletionDialog'
import { TimelineHelpDialog } from './TimelineHelpDialog'
import { useRouter } from 'next/navigation'
import { deleteDocumentLink } from '@/lib/actions/document'

const nodeTypes = {
  document: TimelineGraphNode,
}

const dagreGraph = new dagre.graphlib.Graph()
dagreGraph.setDefaultEdgeLabel(() => ({}))

const nodeWidth = 280
const nodeHeight = 120 // Approximate height for layout

const getLayoutedElements = (nodes: any[], edges: any[], direction = 'TB') => {
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

export function TimelineGraph({ 
  documents, 
  links,
  selectedDocId,
  onSelectDoc 
}: { 
  documents: any[], 
  links: any[],
  selectedDocId?: string | null,
  onSelectDoc?: (id: string) => void
}) {
  const [isPending, startTransition] = useTransition()
  const [showSupporting, setShowSupporting] = useState(true)
  
  // Link Creation State
  const [linkDialogState, setLinkDialogState] = useState<{
    isOpen: boolean;
    sourceDoc: any | null;
    targetDoc: any | null;
  }>({ isOpen: false, sourceDoc: null, targetDoc: null })

  // Link Deletion State
  const [deleteDialogState, setDeleteDialogState] = useState<{
    isOpen: boolean;
    linkId: string | null;
    sourceDoc: any | null;
    targetDoc: any | null;
    linkType?: string | null;
  }>({ isOpen: false, linkId: null, sourceDoc: null, targetDoc: null, linkType: null })
  
  const matterId = documents.length > 0 ? documents[0].matter_id : null

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

  // Build nodes and edges
  const { nodes: initialNodes, edges: initialEdges } = useMemo(() => {
    const nodes = visibleDocuments.map(doc => ({
      id: doc.id,
      type: 'document',
      data: { 
        doc, 
        selected: selectedDocId === doc.id,
      },
      position: { x: 0, y: 0 }, // Dagre will override this
    }))

    const edges = links
      .filter(l => visibleDocIds.has(l.from_doc_id) && visibleDocIds.has(l.to_doc_id)) // Only show links between visible docs
      .map(l => {
        const isManual = l.match_method === 'manual'
        const color = isManual ? '#2563eb' : (l.status === 'pending' ? '#f59e0b' : '#94a3b8')
        return {
          id: l.id,
          source: l.to_doc_id, // "Responds to" means arrow goes from parent to child in a timeline (earlier to later)
          target: l.from_doc_id, // If A responds to B, B is older. Flow goes B -> A
          label: l.link_type?.replace('_', ' ').toUpperCase() || 'LINKS TO',
          type: 'smoothstep',
          animated: l.status === 'pending',
          style: { 
            stroke: color,
            strokeWidth: isManual ? 3 : 2,
            strokeDasharray: (isManual || l.status === 'pending') ? 'none' : '5, 5', // AI inferred (confirmed) is dashed
          },
          labelStyle: { fill: '#64748b', fontWeight: 600, fontSize: 10 },
          labelBgStyle: { fill: '#f8fafc', fillOpacity: 0.9 },
          labelBgPadding: [4, 2] as [number, number],
          labelBgBorderRadius: 4,
          markerEnd: {
            type: MarkerType.ArrowClosed,
            width: 15,
            height: 15,
            color,
          },
        }
      })

    return getLayoutedElements(nodes, edges, 'TB')
  }, [visibleDocuments, visibleDocIds, links, selectedDocId])

  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes)
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges)

  useEffect(() => {
    const { nodes: layoutedNodes, edges: layoutedEdges } = getLayoutedElements(initialNodes, initialEdges, 'TB')
    setNodes(layoutedNodes)
    setEdges(layoutedEdges)
  }, [initialNodes, initialEdges, setNodes, setEdges])

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
          linkId: existingEdge.id,
          sourceDoc,
          targetDoc,
          linkType: (existingEdge as any).label
        })
      }
      return
    }

    if (sourceDoc && targetDoc) {
      setLinkDialogState({
        isOpen: true,
        sourceDoc,
        targetDoc
      })
    }
  }, [visibleDocuments, edges])

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
            {showSupporting ? <EyeOff size={14} className="mr-1.5 text-[var(--text-muted)]" /> : <Eye size={14} className="mr-1.5 text-blue-500" />}
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
            <RefreshCw size={14} className={`mr-1.5 text-amber-500 ${isPending ? 'animate-spin' : ''}`} />
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
            maskColor="var(--surface-hover)"
            className="bg-[var(--surface)] border-[var(--border)] shadow-sm rounded-md"
          />
        </ReactFlow>
      </div>
      
      <LinkCreationDialog
        isOpen={linkDialogState.isOpen}
        sourceDoc={linkDialogState.sourceDoc}
        targetDoc={linkDialogState.targetDoc}
        onClose={() => setLinkDialogState(prev => ({ ...prev, isOpen: false }))}
        onSuccess={() => {}}
      />

      <LinkDeletionDialog
        isOpen={deleteDialogState.isOpen}
        linkId={deleteDialogState.linkId}
        sourceDoc={deleteDialogState.sourceDoc}
        targetDoc={deleteDialogState.targetDoc}
        linkType={deleteDialogState.linkType}
        onClose={() => setDeleteDialogState(prev => ({ ...prev, isOpen: false }))}
      />

      <TimelineHelpDialog
        isOpen={isHelpOpen}
        onClose={() => setIsHelpOpen(false)}
      />
    </div>
  )
}
