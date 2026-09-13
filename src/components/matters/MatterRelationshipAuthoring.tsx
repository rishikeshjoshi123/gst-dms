'use client'

import { startTransition, useId, useLayoutEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { activateTimelineRelationship, archiveTimelineRelationship } from '@/lib/actions/timeline-relationships'
import { canAddTimelineRelationship, proceedingIdentity, reconcileConfirmedRelationshipArchives, relationshipCommandResult, type RelationshipAuthoringContext } from '@/lib/matters/relationship-authoring'
import { describeMatterTimelineRelationship, type MatterTimelineRelationship } from '@/lib/matters/workspace-timeline-page'
import type { MatterTimelineRelationshipProjection } from '@/lib/matters/workspace-read'

const selectClass = 'min-h-11 w-full min-w-0 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 text-sm text-[var(--text-primary)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]'

export function MatterRelationshipAuthoring({ matterId, context, relationship, initialSourceId = '', initialTargetId = '', initiallyOpen = false, onFinish, onArchived }: {
  matterId: string
  context: RelationshipAuthoringContext
  relationship?: MatterTimelineRelationship
  initialSourceId?: string
  initialTargetId?: string
  initiallyOpen?: boolean
  onFinish?: () => void
  onArchived?: (relationshipId: string, revision: number) => void
}) {
  const id = useId()
  const router = useRouter()
  const [open, setOpen] = useState(initiallyOpen)
  const [confirming, setConfirming] = useState(false)
  const [pending, setPending] = useState(false)
  const [sourceId, setSourceId] = useState(initialSourceId)
  const [targetId, setTargetId] = useState(initialTargetId)
  const [type, setType] = useState('')
  const [reason, setReason] = useState('')
  const [message, setMessage] = useState('')
  const request = useRef<{ signature: string; key: string } | null>(null)
  const completed = useRef(false)
  const source = context.documents.find((document) => document.id === sourceId)
  const target = context.documents.find((document) => document.id === targetId)
  const catalogue = context.relationship_types.find((option) => option.relationshipType === type)
  const archive = Boolean(relationship)
  const sourceRecord = relationship ? context.documents.find((document) => document.id === relationship.canonicalSourceDocumentId) : source
  const targetRecord = relationship ? context.documents.find((document) => document.id === relationship.canonicalTargetDocumentId) : target
  const identities = sourceRecord && targetRecord ? `Source — ${sourceRecord.title} (${proceedingIdentity(sourceRecord)}). Target — ${targetRecord.title} (${proceedingIdentity(targetRecord)}).` : ''
  const title = archive ? 'Archive relationship' : 'Add relationship'
  const canonicalSentence = relationship
    ? `${relationship.canonicalSourceTitle} ${relationship.canonicalPhrase} ${relationship.canonicalTargetTitle}`
    : source && target && catalogue ? `${source.title} ${catalogue.canonicalPhrase} ${target.title}` : ''
  const progressionSentence = relationship
    ? `${relationship.canonicalTargetTitle} ${relationship.progressionPhrase} ${relationship.canonicalSourceTitle}`
    : source && target && catalogue ? `${target.title} ${catalogue.progressionPhrase} ${source.title}` : ''
  const valid = !pending && (archive ? reason.trim().length > 0 : Boolean(source && target && source.id !== target.id && catalogue))

  async function submit() {
    if (!valid || pending) return
    const payload = relationship
      ? { matterId, relationshipId: relationship.id, revision: relationship.revision, reason: reason.trim() }
      : source && target && catalogue ? { matterId, sourceId: source.id, targetId: target.id, sourceRevision: source.lifecycleRevision, targetRevision: target.lifecycleRevision, relationshipType: catalogue.relationshipType, reason: reason.trim() } : null
    if (!payload) return
    const signature = JSON.stringify(payload)
    if (request.current?.signature !== signature) request.current = { signature, key: crypto.randomUUID() }
    const idempotencyKey = request.current.key
    setPending(true)
    try {
      const result = payload.relationshipId !== undefined
        ? await archiveTimelineRelationship({ ...payload, idempotencyKey })
        : await activateTimelineRelationship({ ...payload, idempotencyKey })
      setMessage(result.message)
      setConfirming(false)
      if (result.refresh) startTransition(() => router.refresh())
      if (result.ok) {
        completed.current = true
        setOpen(false)
        setReason('')
        request.current = null
        onFinish?.()
        if (relationship) onArchived?.(relationship.id, relationship.revision)
        if (relationship) document.getElementById(`matter-inspector-${matterId}`)?.focus()
      }
    } catch {
      setMessage(relationshipCommandResult('unknown').message)
      setConfirming(false)
    } finally { setPending(false) }
  }

  if (!archive && !canAddTimelineRelationship(context)) return null

  return <>
    <Dialog open={open} onOpenChange={(value) => { if (!pending) { setOpen(value); setMessage(''); if (!value) onFinish?.() } }}>
      <DialogTrigger asChild><Button type="button" variant={archive ? 'outline' : 'default'}>{title}</Button></DialogTrigger>
      <DialogContent showClose={!pending} onCloseAutoFocus={(event) => {
        if (relationship && completed.current) {
          event.preventDefault()
          document.getElementById(`matter-inspector-${matterId}`)?.focus()
        }
      }} className="flex max-h-[85dvh] flex-col overflow-hidden">
        <DialogHeader className="shrink-0"><DialogTitle>{title}</DialogTitle><DialogDescription>{archive ? 'Explain why this relationship should stop defining the Timeline. Decision history is retained.' : 'First choose the source that performs the action, then choose its target. Review both directions before saving.'}</DialogDescription></DialogHeader>
        <div className="custom-scrollbar min-h-0 min-w-0 flex-1 space-y-3 overflow-y-auto py-3">
          {!archive && <>
            <div className="space-y-1"><Label htmlFor={`${id}-source`}>1. Choose source document</Label><select id={`${id}-source`} className={selectClass} value={sourceId} disabled={pending} onChange={(event) => { setSourceId(event.target.value); if (event.target.value === targetId) setTargetId('') }}><option value="">Select the document performing the action</option>{context.documents.map((document) => <option key={document.id} value={document.id}>{document.title} — {proceedingIdentity(document)}</option>)}</select></div>
            <div className="space-y-1"><Label htmlFor={`${id}-target`}>2. Choose target document</Label><select id={`${id}-target`} className={selectClass} value={targetId} disabled={pending || !source} onChange={(event) => setTargetId(event.target.value)}><option value="">Select the document acted on</option>{context.documents.filter((document) => document.id !== sourceId).map((document) => <option key={document.id} value={document.id}>{document.title} — {proceedingIdentity(document)}</option>)}</select></div>
            <div className="space-y-1"><Label htmlFor={`${id}-type`}>3. Choose relationship</Label><select id={`${id}-type`} className={selectClass} value={type} disabled={pending || !target} onChange={(event) => setType(event.target.value)}><option value="">Select the action</option>{context.relationship_types.map((option) => <option key={option.relationshipType} value={option.relationshipType}>{option.canonicalPhrase}</option>)}</select></div>
          </>}
          {canonicalSentence && <dl className="space-y-2 break-words text-sm"><div><dt className="text-[var(--text-muted)]">Canonical relationship</dt><dd>{canonicalSentence}</dd></div><div><dt className="text-[var(--text-muted)]">Timeline progression</dt><dd>{progressionSentence}</dd></div></dl>}
          {identities && <p className="break-words text-sm text-[var(--text-secondary)]">{identities}</p>}
          <div className="space-y-1"><Label htmlFor={`${id}-reason`}>{archive ? 'Reason for archiving' : 'Reason (optional)'}</Label><Input id={`${id}-reason`} value={reason} maxLength={500} required={archive} disabled={pending} onChange={(event) => setReason(event.target.value)} /></div>
          {message && <p role="status" className="text-sm text-[var(--text-secondary)]">{message}</p>}
        </div>
        <DialogFooter className="shrink-0"><Button variant="ghost" disabled={pending} onClick={() => { setOpen(false); onFinish?.() }}>Cancel</Button><Button disabled={!valid} onClick={() => setConfirming(true)}>Review {archive ? 'archive' : 'relationship'}</Button></DialogFooter>
        <ConfirmDialog isOpen={confirming} onClose={() => setConfirming(false)} onConfirm={() => startTransition(submit)} title={`${title}?`} description={`${identities} ${canonicalSentence}. Timeline progression: ${progressionSentence}.${archive ? ` Reason: ${reason.trim()}. This relationship will leave the effective Timeline; its decision history remains.` : ''}`} confirmText={title} variant={archive ? 'destructive' : 'default'} isPending={pending} />
      </DialogContent>
    </Dialog>
    {!open && message && <p role="status" className="text-sm text-[var(--text-secondary)]">{message}</p>}
  </>
}

export function MatterEffectiveRelationshipList({ matterId, selectedDocumentId, projection, context }: {
  matterId: string
  selectedDocumentId: string
  projection: MatterTimelineRelationshipProjection
  context?: RelationshipAuthoringContext | null
}) {
  const [confirmedArchives, setConfirmedArchives] = useState<Record<string, number>>({})
  useLayoutEffect(() => {
    if (Object.keys(confirmedArchives).length > 0) document.getElementById(`matter-inspector-${matterId}`)?.focus({ preventScroll: true })
  }, [confirmedArchives, matterId])
  const relationships = reconcileConfirmedRelationshipArchives(projection.relationships, confirmedArchives)
  if (projection.outcome === 'unavailable') return <p role="status" className="mt-2 text-[var(--text-secondary)]">Relationships are temporarily unavailable.</p>
  if (relationships.length === 0) return <p className="mt-2 text-[var(--text-secondary)]">No active Timeline relationships involve this proceeding.</p>
  return <ol className="mt-3 space-y-3">{relationships.map((relationship) => {
    const description = describeMatterTimelineRelationship(relationship, selectedDocumentId)
    return <li key={relationship.id} className="border border-[var(--border)] bg-[var(--surface)] p-3"><p className="text-xs font-medium uppercase tracking-wide text-[var(--text-muted)]">{description.direction === 'outgoing' ? 'Outgoing' : 'Incoming'} · {relationship.verification === 'human' ? 'Human verified' : relationship.verification === 'policy_confirmed' ? 'Policy confirmed' : 'Provisional'}</p><p className="mt-2 text-[var(--text-primary)]">{description.canonicalSentence}</p><dl className="mt-2 border-t border-[var(--border)] pt-2"><dt className="text-xs text-[var(--text-muted)]">Timeline progression</dt><dd className="mt-1 text-[var(--text-secondary)]">{description.progressionSentence}</dd></dl>{context && <div className="mt-3"><MatterRelationshipAuthoring matterId={matterId} context={context} relationship={relationship} onArchived={(id, revision) => setConfirmedArchives((current) => ({ ...current, [id]: Math.max(current[id] ?? 0, revision) }))} /></div>}</li>
  })}</ol>
}
