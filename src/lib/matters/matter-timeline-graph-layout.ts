import dagre from 'dagre'

import type {
  MatterTimelineChronologyItem,
  MatterTimelineRelationship,
} from './workspace-timeline-page'
import { shapeMatterTimelineRelationships } from './workspace-timeline-page'

export const MATTER_TIMELINE_NODE_WIDTH = 184
export const MATTER_TIMELINE_NODE_HEIGHT = 120
const GRAPH_MARGIN = 48
const UNLINKED_LANE_GAP = 120
const UNLINKED_NODE_GAP = 72

export type MatterTimelineGraphNodeLayout = {
  id: string
  document: MatterTimelineChronologyItem
  position: { x: number; y: number }
  width: typeof MATTER_TIMELINE_NODE_WIDTH
  height: typeof MATTER_TIMELINE_NODE_HEIGHT
  unlinked: boolean
}

export type MatterTimelineGraphEdgeLayout = {
  id: string
  displayFromDocumentId: string
  displayToDocumentId: string
  canonicalSourceDocumentId: string
  label: string
  primaryPhrase: string
  relationships: MatterTimelineRelationship[]
}

export type MatterTimelineGraphLayout = {
  nodes: MatterTimelineGraphNodeLayout[]
  edges: MatterTimelineGraphEdgeLayout[]
  width: number
  height: number
  unlinkedLaneY: number | null
}

function compareDocuments(
  left: MatterTimelineChronologyItem,
  right: MatterTimelineChronologyItem,
) {
  if (left.effectiveDate === null && right.effectiveDate !== null) return 1
  if (left.effectiveDate !== null && right.effectiveDate === null) return -1
  const byDate = (left.effectiveDate ?? '').localeCompare(right.effectiveDate ?? '')
  return byDate || left.id.localeCompare(right.id)
}

/**
 * Unlike the selected-proceeding inspector, a whole-graph projection cannot
 * safely discard one malformed secured row and present the remaining edges as
 * complete. Preserve the projection count or reject it in full.
 */
export function shapeMatterTimelineGraphRelationships(value: unknown) {
  if (!Array.isArray(value)) return { outcome: 'unavailable' as const, relationships: [] }
  const relationships = shapeMatterTimelineRelationships(value)
  return relationships.length === value.length
    && new Set(relationships.map((relationship) => relationship.id)).size === relationships.length
    ? { outcome: 'ok' as const, relationships }
    : { outcome: 'unavailable' as const, relationships: [] }
}

export function shapeMatterTimelineGraphRelationshipProjection(value: unknown) {
  const unavailable = {
    outcome: 'unavailable' as const,
    relationships: [] as MatterTimelineRelationship[],
    sourceRevision: null,
    fetchedAt: null,
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) return unavailable
  const row = value as Record<string, unknown>
  if (row.outcome !== 'ok'
    || (typeof row.source_revision !== 'string' && row.source_revision !== null)
    || typeof row.fetched_at !== 'string') return unavailable
  const shaped = shapeMatterTimelineGraphRelationships(row.relationships)
  if (shaped.outcome !== 'ok') return unavailable
  return {
    outcome: 'ok' as const,
    relationships: shaped.relationships,
    sourceRevision: row.source_revision,
    fetchedAt: row.fetched_at,
  }
}

function bundleRelationships(relationships: readonly MatterTimelineRelationship[]) {
  const bundles = new Map<string, MatterTimelineRelationship[]>()
  // The secured projection is already ordered by catalogue display priority,
  // then relationship type and ID. Preserve that catalogue-owned order here.
  for (const relationship of relationships) {
    const key = `${relationship.displayFromDocumentId}\u0000${relationship.displayToDocumentId}`
    const bundle = bundles.get(key)
    if (bundle) bundle.push(relationship)
    else bundles.set(key, [relationship])
  }
  return [...bundles.values()]
    .map((bundle): MatterTimelineGraphEdgeLayout => {
      const primary = bundle[0]
      return {
        id: `timeline-edge:${primary.displayFromDocumentId}:${primary.displayToDocumentId}`,
        displayFromDocumentId: primary.displayFromDocumentId,
        displayToDocumentId: primary.displayToDocumentId,
        canonicalSourceDocumentId: primary.canonicalSourceDocumentId,
        label: `${primary.progressionPhrase}${bundle.length > 1 ? ` +${bundle.length - 1}` : ''}`,
        primaryPhrase: primary.progressionPhrase,
        relationships: bundle,
      }
    })
    .sort((left, right) => left.id.localeCompare(right.id))
}

function measuredExtent(nodes: readonly MatterTimelineGraphNodeLayout[]) {
  return nodes.reduce((extent, node) => ({
    width: Math.max(extent.width, node.position.x + MATTER_TIMELINE_NODE_WIDTH + GRAPH_MARGIN),
    height: Math.max(extent.height, node.position.y + MATTER_TIMELINE_NODE_HEIGHT + GRAPH_MARGIN),
  }), { width: MATTER_TIMELINE_NODE_WIDTH + GRAPH_MARGIN * 2, height: MATTER_TIMELINE_NODE_HEIGHT + GRAPH_MARGIN * 2 })
}

/**
 * A deterministic, domain-free LR Dagre adapter. Stored relationship direction
 * is never mutated: only the catalogue-projected display endpoints are laid out.
 */
export function layoutMatterTimelineGraph(
  documents: readonly MatterTimelineChronologyItem[],
  relationships: readonly MatterTimelineRelationship[],
): MatterTimelineGraphLayout {
  const sortedDocuments = [...documents].sort(compareDocuments)
  const documentIds = new Set(sortedDocuments.map((document) => document.id))
  const eligibleRelationships = relationships.filter((relationship) => (
    documentIds.has(relationship.displayFromDocumentId)
    && documentIds.has(relationship.displayToDocumentId)
  ))
  const edges = bundleRelationships(eligibleRelationships)
  const linkedIds = new Set(edges.flatMap((edge) => [edge.displayFromDocumentId, edge.displayToDocumentId]))
  const linked = sortedDocuments.filter((document) => linkedIds.has(document.id))
  const unlinked = sortedDocuments.filter((document) => !linkedIds.has(document.id))

  const graph = new dagre.graphlib.Graph({ directed: true, multigraph: false, compound: false })
  graph.setDefaultEdgeLabel(() => ({}))
  graph.setGraph({
    rankdir: 'LR',
    ranker: 'network-simplex',
    ranksep: 160,
    nodesep: 88,
    edgesep: 56,
    marginx: GRAPH_MARGIN,
    marginy: GRAPH_MARGIN,
  })
  for (const document of linked) {
    graph.setNode(document.id, {
      width: MATTER_TIMELINE_NODE_WIDTH,
      height: MATTER_TIMELINE_NODE_HEIGHT,
    })
  }
  for (const edge of edges) graph.setEdge(edge.displayFromDocumentId, edge.displayToDocumentId)
  if (linked.length > 0) dagre.layout(graph)

  const positionedByDocumentId = new Map(linked.map((document) => {
    const positioned = graph.node(document.id)
    if (!positioned || !Number.isFinite(positioned.x) || !Number.isFinite(positioned.y)) {
      throw new Error('Timeline layout did not position every proceeding.')
    }
    return [document.id, positioned] as const
  }))
  const verticalSlotsByRank = new Map<number, number[]>()
  for (const positioned of positionedByDocumentId.values()) {
    const slots = verticalSlotsByRank.get(positioned.x) ?? []
    slots.push(positioned.y)
    verticalSlotsByRank.set(positioned.x, slots)
  }
  for (const slots of verticalSlotsByRank.values()) slots.sort((left, right) => left - right)
  const nextSlotByRank = new Map<number, number>()

  // Dagre is free to optimize edge crossings by reordering siblings. Reassign
  // its non-overlapping y slots so every visual rank remains chronological.
  const linkedNodes = linked.map((document): MatterTimelineGraphNodeLayout => {
    const positioned = positionedByDocumentId.get(document.id)
    if (!positioned) throw new Error('Timeline layout lost a positioned proceeding.')
    const slotIndex = nextSlotByRank.get(positioned.x) ?? 0
    const y = verticalSlotsByRank.get(positioned.x)?.[slotIndex]
    if (y === undefined || !Number.isFinite(y)) throw new Error('Timeline layout lost a vertical rank slot.')
    nextSlotByRank.set(positioned.x, slotIndex + 1)
    return {
      id: document.id,
      document,
      position: {
        x: positioned.x - MATTER_TIMELINE_NODE_WIDTH / 2,
        y: y - MATTER_TIMELINE_NODE_HEIGHT / 2,
      },
      width: MATTER_TIMELINE_NODE_WIDTH,
      height: MATTER_TIMELINE_NODE_HEIGHT,
      unlinked: false,
    }
  })
  const connectedExtent = measuredExtent(linkedNodes)
  const unlinkedLaneY = unlinked.length > 0
    ? linkedNodes.length > 0 ? connectedExtent.height + UNLINKED_LANE_GAP : GRAPH_MARGIN
    : null
  const unlinkedNodes = unlinked.map((document, index): MatterTimelineGraphNodeLayout => ({
    id: document.id,
    document,
    position: {
      x: GRAPH_MARGIN + index * (MATTER_TIMELINE_NODE_WIDTH + UNLINKED_NODE_GAP),
      y: unlinkedLaneY ?? GRAPH_MARGIN,
    },
    width: MATTER_TIMELINE_NODE_WIDTH,
    height: MATTER_TIMELINE_NODE_HEIGHT,
    unlinked: true,
  }))
  const nodes = [...linkedNodes, ...unlinkedNodes]
  return { nodes, edges, ...measuredExtent(nodes), unlinkedLaneY }
}
