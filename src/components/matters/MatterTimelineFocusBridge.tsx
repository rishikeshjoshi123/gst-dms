'use client'

import Link from 'next/link'
import { createContext, useCallback, useContext, useLayoutEffect, useMemo, useRef, type ReactNode } from 'react'

type FocusBridge = {
  remember: (documentId: string) => void
  registerRow: (documentId: string, node: HTMLAnchorElement | null) => void
  commit: (selectedDocumentId: string | null, matterId: string) => void
}

const MatterTimelineFocusContext = createContext<FocusBridge | null>(null)

export function MatterTimelineFocusProvider({ children }: { children: ReactNode }) {
  const pendingId = useRef<string | null>(null)
  const committedClear = useRef(false)
  const rows = useRef(new Map<string, HTMLAnchorElement>())

  const focusPending = useCallback((matterId: string, allowFallback: boolean) => {
    const documentId = pendingId.current
    if (!documentId) return false
    const row = rows.current.get(documentId)
    if (row?.isConnected) {
      row.focus({ preventScroll: true })
      pendingId.current = null
      committedClear.current = false
      return true
    }
    if (allowFallback) {
      const fallback = document.getElementById(`matter-timeline-filter-${matterId}`)
        ?? document.getElementById(`matter-timeline-chronology-${matterId}`)
      fallback?.focus({ preventScroll: true })
      pendingId.current = null
      committedClear.current = false
    }
    return false
  }, [])

  const value = useMemo<FocusBridge>(() => ({
    remember(documentId) {
      pendingId.current = documentId
      committedClear.current = false
    },
    registerRow(documentId, node) {
      if (node) rows.current.set(documentId, node)
      else rows.current.delete(documentId)
      if (node && committedClear.current && pendingId.current === documentId) {
        node.focus({ preventScroll: true })
        pendingId.current = null
        committedClear.current = false
      }
    },
    commit(selectedDocumentId, matterId) {
      if (selectedDocumentId !== null || !pendingId.current) return
      committedClear.current = true
      if (!focusPending(matterId, false)) {
        requestAnimationFrame(() => focusPending(matterId, true))
      }
    },
  }), [focusPending])

  return <MatterTimelineFocusContext.Provider value={value}>{children}</MatterTimelineFocusContext.Provider>
}

function useFocusBridge() {
  const bridge = useContext(MatterTimelineFocusContext)
  if (!bridge) throw new Error('Matter Timeline focus controls require their provider.')
  return bridge
}

export function MatterTimelineRowLink({ documentId, href, children, className, ariaLabel, selected }: { documentId: string; href: string; children: ReactNode; className: string; ariaLabel?: string; selected?: boolean }) {
  const bridge = useFocusBridge()
  return <Link id={`matter-timeline-row-${documentId}`} ref={(node) => bridge.registerRow(documentId, node)} href={href} scroll={false} prefetch={false} aria-label={ariaLabel} aria-current={selected ? 'true' : undefined} className={className}>{children}</Link>
}

export function MatterTimelineCloseLink({ documentId, href, children, className }: { documentId: string; href: string; children: ReactNode; className: string }) {
  const bridge = useFocusBridge()
  return <Link href={href} scroll={false} onNavigate={() => bridge.remember(documentId)} className={className}>{children}</Link>
}

export function MatterTimelineFocusCommit({ selectedDocumentId, matterId, snapshot }: { selectedDocumentId: string | null; matterId: string; snapshot: string }) {
  const bridge = useFocusBridge()
  useLayoutEffect(() => bridge.commit(selectedDocumentId, matterId), [bridge, matterId, selectedDocumentId, snapshot])
  return null
}
