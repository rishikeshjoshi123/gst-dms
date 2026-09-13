'use client'

import dynamic from 'next/dynamic'
import { startTransition, useEffect, useRef, useState, type ReactNode } from 'react'

import type { MatterTimelineGraphProjection } from '@/lib/matters/workspace-read'
import { shouldRequestMatterTimelineGraph } from '@/lib/matters/workspace-route'
import type { RelationshipAuthoringContext } from '@/lib/matters/relationship-authoring'

const MatterTimelineGraphCanvas = dynamic(() => import('./MatterTimelineGraphCanvas'), {
  ssr: false,
  loading: () => <p role="status" className="p-4 text-sm text-[var(--text-secondary)]">Loading timeline graph…</p>,
})

export function MatterTimelineAdaptiveGraph(props: {
  authoringContext?: RelationshipAuthoringContext | null
  matterId: string
  loadGraph: () => Promise<MatterTimelineGraphProjection>
  graphRequestKey: string
  graphContextKey: string
  selectedDocumentId: string | null
  queryEntries: Array<[string, string]>
  chronologyHref: string
  inspector: ReactNode
  chronology: ReactNode
  filters: string[]
}) {
  const [desktopCapable, setDesktopCapable] = useState(false)
  const [loaded, setLoaded] = useState<{ requestKey: string; contextKey: string; graph: MatterTimelineGraphProjection } | null>(null)
  const [loadingKey, setLoadingKey] = useState<string | null>(null)
  const loadGraphRef = useRef(props.loadGraph)

  useEffect(() => {
    loadGraphRef.current = props.loadGraph
  }, [props.loadGraph])

  useEffect(() => {
    const media = window.matchMedia('(min-width: 1024px)')
    let disposed = false
    let requested = false
    const requestKey = props.graphRequestKey
    const contextKey = props.graphContextKey
    const update = () => {
      setDesktopCapable(media.matches)
      if (!shouldRequestMatterTimelineGraph(media.matches, requested)) return
      requested = true
      setLoadingKey(requestKey)
      startTransition(async () => {
        try {
          const projection = await loadGraphRef.current()
          if (!disposed) setLoaded({ requestKey, contextKey, graph: projection })
        } catch {
          if (!disposed) setLoaded({
            requestKey,
            contextKey,
            graph: {
              outcome: 'unavailable', reason: 'read', layout: null,
              total: 0, unfilteredTotal: 0, sourceRevision: null,
              relationshipSourceRevision: null, fetchedAt: new Date().toISOString(),
            },
          })
        } finally {
          if (!disposed) setLoadingKey((current) => current === requestKey ? null : current)
        }
      })
    }
    update()
    media.addEventListener('change', update)
    return () => {
      disposed = true
      media.removeEventListener('change', update)
    }
  }, [props.graphRequestKey, props.graphContextKey])

  // Keep world coordinates and open drafts during a same-scope refresh. Other context
  // changes must never display a projection belonging to different filters.
  const graph = loaded?.requestKey === props.graphRequestKey || loaded?.contextKey === props.graphContextKey ? loaded.graph : null
  const loading = loadingKey === props.graphRequestKey
  if (!desktopCapable || !graph) {
    return <>{desktopCapable && loading ? <p role="status" className="sr-only">Preparing timeline graph…</p> : null}{props.chronology}</>
  }
  if (graph.outcome !== 'ok' || !graph.layout) {
    const message = graph.reason === 'capacity'
      ? 'This matter has more than 250 matching proceedings. Narrow the filters to use Graph.'
      : 'The graph could not be prepared. The authoritative chronology remains available.'
    return (
      <div className="flex h-full min-h-0 flex-col gap-2 [&_[data-timeline-graph-action]]:hidden">
        <p role="status" className="shrink-0 border border-[var(--border)] bg-[var(--surface)] p-3 text-sm text-[var(--text-secondary)]">{message}</p>
        <div className="min-h-0 flex-1">{props.chronology}</div>
      </div>
    )
  }

  const filteredCountLabel = graph.total === graph.unfilteredTotal
    ? `${graph.total} proceeding${graph.total === 1 ? '' : 's'}`
    : `Showing ${graph.total} of ${graph.unfilteredTotal} proceedings`
  return <MatterTimelineGraphCanvas {...props} layout={graph.layout} filteredCountLabel={filteredCountLabel} />
}
