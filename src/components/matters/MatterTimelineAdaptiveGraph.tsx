'use client'

import dynamic from 'next/dynamic'
import { useEffect, useState, type ReactNode } from 'react'

import type { MatterTimelineGraphLayout } from '@/lib/matters/matter-timeline-graph-layout'

const MatterTimelineGraphCanvas = dynamic(() => import('./MatterTimelineGraphCanvas'), {
  ssr: false,
  loading: () => <p role="status" className="p-4 text-sm text-[var(--text-secondary)]">Loading timeline graph…</p>,
})

export function MatterTimelineAdaptiveGraph(props: {
  matterId: string
  layout: MatterTimelineGraphLayout
  selectedDocumentId: string | null
  queryEntries: Array<[string, string]>
  chronologyHref: string
  inspector: ReactNode
  chronology: ReactNode
  filteredCountLabel: string
  filters: string[]
}) {
  const [desktopCapable, setDesktopCapable] = useState(false)

  useEffect(() => {
    const media = window.matchMedia('(min-width: 1024px)')
    const update = () => setDesktopCapable(media.matches)
    update()
    media.addEventListener('change', update)
    return () => media.removeEventListener('change', update)
  }, [])

  if (!desktopCapable) return props.chronology
  return <MatterTimelineGraphCanvas {...props} />
}
