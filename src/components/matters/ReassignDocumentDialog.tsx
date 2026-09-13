'use client'

import { useEffect, useRef, useState, useTransition } from 'react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { getMatters } from '@/lib/actions/matter'
import { previewDocumentBoundaryRepair, reassignDocumentMatter, type BoundaryRepairImpact } from '@/lib/actions/document'
import { toast } from 'sonner'

function BoundaryRepairDialog({ isOpen, onClose, documentId, currentMatterId }: {
  isOpen: boolean; onClose: () => void; documentId: string; currentMatterId: string
}) {
  const [matters, setMatters] = useState<Awaited<ReturnType<typeof getMatters>>>([])
  const [target, setTarget] = useState('')
  const [mode, setMode] = useState<'move' | 'copy'>('move')
  const [search, setSearch] = useState('')
  const [reason, setReason] = useState('')
  const [impact, setImpact] = useState<BoundaryRepairImpact | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [pending, startTransition] = useTransition()
  const [reload, setReload] = useState(0)
  const confirmationKey = useRef<string | null>(null)
  const impactHeading = useRef<HTMLSpanElement>(null)
  const generation = useRef(0)

  useEffect(() => {
    const request = ++generation.current
    if (!isOpen) return
    getMatters().then((rows) => {
      if (request === generation.current) setMatters(rows)
    }).catch(() => {
      if (request === generation.current) setError('Could not load Matters. Retry to choose a target.')
    }).finally(() => {
      if (request === generation.current) setLoading(false)
    })
    return () => { generation.current = request + 1 }
  }, [isOpen, documentId, currentMatterId, reload])

  useEffect(() => { if (impact) impactHeading.current?.focus() }, [impact])

  const reviewImpact = () => {
    const request = generation.current
    setError('')
    startTransition(async () => {
      try {
        const result = await previewDocumentBoundaryRepair(documentId, target, mode)
        if (request !== generation.current) return
        if ('impact' in result && result.impact) {
          confirmationKey.current = crypto.randomUUID()
          setImpact(result.impact)
        } else setError(result.error ?? 'Could not load the impact. Please retry.')
      } catch { if (request === generation.current) setError('Could not load the impact. Please retry.') }
    })
  }

  const confirm = () => {
    if (!impact || !confirmationKey.current) return
    const request = generation.current
    const idempotencyKey = confirmationKey.current
    setError('')
    startTransition(async () => {
      try {
        const result = await reassignDocumentMatter(documentId, target, mode, { fingerprint: impact.fingerprint, reason, idempotencyKey })
        if (request !== generation.current) return
        if ('error' in result) {
          setError(result.error ?? 'The change could not be completed.')
          if (result.code === 'stale_preview' || result.code === 'idempotency_conflict') {
            setImpact(null); confirmationKey.current = null
          }
        } else {
          toast.success(mode === 'move' ? 'Document moved' : 'Document copied')
          onClose()
        }
      } catch { if (request === generation.current) setError('Confirmation could not be verified. Retry to check the same change.') }
    })
  }

  const available = matters.filter((matter) => matter.id !== currentMatterId && matter.work_state !== 'closed'
    && `${matter.title} ${matter.matter_code ?? ''}`.toLowerCase().includes(search.toLowerCase()))

  return <Dialog open={isOpen} onOpenChange={(open) => { if (!open && !pending) onClose() }}>
    <DialogContent showClose={false} className="flex max-h-[85dvh] flex-col overflow-hidden sm:max-w-lg"
      onEscapeKeyDown={(event) => { if (pending) event.preventDefault() }}
      onPointerDownOutside={(event) => { if (pending) event.preventDefault() }}>
      <DialogHeader className="shrink-0">
        <DialogTitle><span ref={impactHeading} tabIndex={-1}>{impact ? `Confirm document ${mode}` : 'Move or copy document'}</span></DialogTitle>
        <DialogDescription className="line-clamp-3 break-words">{impact
          ? `${impact.documentTitle} · ${impact.sourceMatterTitle} → ${impact.targetMatterTitle}`
          : 'Repair the placement of one document. Create the target Matter separately before continuing.'}</DialogDescription>
      </DialogHeader>
      <div className="min-h-0 overflow-y-auto overscroll-contain custom-scrollbar space-y-4" aria-busy={pending || loading}>
        {loading ? <p role="status">Loading Matters…</p> : impact ? <>
          <p className="text-sm text-[var(--text-secondary)]">{mode === 'move'
            ? 'The document, versions, notes, exact citations, deadlines and tasks move together. Effective relationships are archived with your reason. Document identifiers and source facts remain attached to this document.'
            : 'A distinct document will share the same PDF and base analysis. Original notes, citations, deadlines and tasks remain with the original. Human field decisions are preserved with their source provenance. Verified Matter and document identifiers are not duplicated.'}</p>
          <dl className="divide-y divide-[var(--border-subtle)] text-sm">
            <div className="flex justify-between gap-4 py-2"><dt>Shared PDF assets</dt><dd>{impact.sharedAssets}</dd></div>
            {impact.categories.map((item) => <div key={item.key} className="flex justify-between gap-4 py-2"><dt>{item.label}</dt><dd className="tabular-nums">{item.count}</dd></div>)}
          </dl>
          {impact.blockers.length > 0 && <div role="alert" className="text-sm text-[var(--danger)]"><p>This repair is blocked:</p><ul className="list-disc pl-5">{impact.blockers.map((blocker) => <li key={blocker}>{blocker}</li>)}</ul></div>}
          <div className="space-y-2"><Label htmlFor="repair-reason">Reason for this {mode}</Label>
            <Input id="repair-reason" value={reason} maxLength={500} disabled={pending}
              onChange={(event) => { setReason(event.target.value); confirmationKey.current = crypto.randomUUID() }} aria-describedby="repair-reason-help" />
            <p id="repair-reason-help" className="text-xs text-[var(--text-muted)]">Required, up to 500 characters. Recorded with this change.</p>
          </div>
        </> : <>
          <div className="flex flex-wrap gap-2" role="group" aria-label="Repair action">
            <Button variant={mode === 'move' ? 'default' : 'outline'} aria-pressed={mode === 'move'} disabled={pending} onClick={() => setMode('move')}>Move document</Button>
            <Button variant={mode === 'copy' ? 'default' : 'outline'} aria-pressed={mode === 'copy'} disabled={pending} onClick={() => setMode('copy')}>Copy document</Button>
          </div>
          <div className="space-y-2"><Label htmlFor="repair-matter-search">Find target Matter</Label><Input id="repair-matter-search" value={search} disabled={pending} onChange={(event) => { setSearch(event.target.value); setTarget('') }} placeholder="Search title or Matter code" /></div>
          <div className="space-y-2" role="group" aria-label="Target Matter">
            {available.length === 0 ? <p className="text-sm text-[var(--text-muted)]">No other active Matters match. Create the target Matter first, or change your search.</p>
              : available.map((matter) => <Button key={matter.id} variant={target === matter.id ? 'secondary' : 'outline'} aria-pressed={target === matter.id}
                disabled={pending} onClick={() => setTarget(matter.id)} className="h-auto min-h-11 w-full justify-start whitespace-normal text-left">
                <span className="min-w-0 break-words">{matter.title}<span className="block text-xs text-[var(--text-muted)]">{matter.matter_code}</span></span>
              </Button>)}
          </div>
        </>}
        {error && <p role="alert" className="text-sm text-[var(--danger)]">{error}</p>}
      </div>
      <DialogFooter className="shrink-0">
        <Button variant="outline" disabled={pending} onClick={() => { if (impact) { setImpact(null); setError(''); confirmationKey.current = null } else onClose() }}>{impact ? 'Back' : 'Cancel'}</Button>
        {loading ? null : error && matters.length === 0 ? <Button onClick={() => { setLoading(true); setError(''); setReload(reload + 1) }}>Retry loading Matters</Button>
          : impact ? <Button disabled={pending || !reason.trim() || impact.blockers.length > 0} onClick={confirm}>{pending ? 'Confirming…' : mode === 'move' ? 'Move document' : 'Copy document'}</Button>
            : <Button disabled={pending || !target} onClick={reviewImpact}>{pending ? 'Loading impact…' : 'Review impact'}</Button>}
      </DialogFooter>
    </DialogContent>
  </Dialog>
}

export function ReassignDocumentDialog(props: { isOpen: boolean; onClose: () => void; documentId: string; currentMatterId: string }) {
  return props.isOpen ? <BoundaryRepairDialog key={`${props.documentId}:${props.currentMatterId}`} {...props} /> : null
}
