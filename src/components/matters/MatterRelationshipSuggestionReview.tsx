'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useState, useTransition } from 'react'

import { resolveRelationshipSuggestion } from '@/lib/actions/review'
import { canonicalDocumentPath } from '@/lib/canonical-document-route'
import type { RelationshipSuggestionResolution, ReviewDetail } from '@/lib/review/model'
import { relationshipSuggestionEvidence } from '@/lib/review/relationship-suggestion'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'

export function MatterRelationshipSuggestionReview({
  initialItem,
  requestedRevision,
  returnTo,
}: {
  initialItem: ReviewDetail | null
  requestedRevision: number
  returnTo: string
}) {
  const router = useRouter()
  const [item, setItem] = useState(initialItem)
  const [action, setAction] = useState<RelationshipSuggestionResolution['action'] | ''>('')
  const [relationshipType, setRelationshipType] = useState('refers_to')
  const [reverse, setReverse] = useState(false)
  const [reason, setReason] = useState('')
  const [message, setMessage] = useState('')
  const [confirming, setConfirming] = useState(false)
  const [pending, startTransition] = useTransition()
  const evidence = item ? relationshipSuggestionEvidence(item) : null
  const catalogue = item?.relationship_catalogue ?? []
  const selectedCatalogue = catalogue.find((entry) => entry.relationship_type === relationshipType)
  const canResolve = Boolean(item?.status === 'needs_review' && item.allowed_actions.length > 0 && evidence)
  const linkWasStale = Boolean(item && item.revision !== requestedRevision)

  function submit() {
    if (!item || !evidence || !action || reason.trim().length < 2) return
    const reject = action === 'reject_relationship'
    const corrected = action === 'correct_relationship'
    const selectedType = corrected ? selectedCatalogue : catalogue.find((entry) => entry.relationship_type === 'refers_to')
    const sourceDocumentId = reverse && corrected ? evidence.target_document_id : evidence.source_document_id
    const targetDocumentId = reverse && corrected ? evidence.source_document_id : evidence.target_document_id
    const payload: RelationshipSuggestionResolution = {
      itemId: item.id,
      revision: item.revision,
      action,
      relationshipType: reject ? null : corrected ? selectedCatalogue?.relationship_type ?? null : 'refers_to',
      catalogueVersion: reject ? null : selectedType?.catalogue_version ?? item.suggested_catalogue_version ?? null,
      sourceDocumentId: reject ? null : sourceDocumentId,
      targetDocumentId: reject ? null : targetDocumentId,
      reason,
      idempotencyKey: crypto.randomUUID(),
    }
    startTransition(async () => {
      try {
        const result = await resolveRelationshipSuggestion(payload)
        setMessage(result.message)
        if (result.item) setItem(result.item)
        if (result.code !== 'failed') {
          setConfirming(false)
          setAction('')
          setReason('')
          router.refresh()
        }
      } catch {
        setMessage('The relationship decision could not be recorded. Retry from the current item.')
      }
    })
  }

  if (!item || item.type !== 'relationship_suggestion' || !evidence) {
    return <aside className="custom-scrollbar min-h-0 w-full overflow-y-auto rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4 lg:w-96" aria-label="Relationship Review">
      <h2 className="text-section-heading">Relationship Review unavailable</h2>
      <p className="mt-2 text-sm text-[var(--text-secondary)]">This exact Review item is unavailable in the current Matter. No relationship was changed.</p>
      <Link href={returnTo} className="mt-4 inline-flex min-h-11 items-center rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 text-sm font-medium">Return to Review</Link>
    </aside>
  }

  const outcome = item.last_decision?.action
  return <aside className="custom-scrollbar min-h-0 w-full overflow-y-auto rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] lg:w-96" aria-label="Exact reference relationship Review">
    <header className="sticky top-0 z-10 space-y-2 border-b border-[var(--border)] bg-[var(--surface)] p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-section-heading">Review exact reference</h2>
        <Badge variant={item.status === 'closed' ? 'muted' : 'warning'} fixedWidth="lg">{item.status === 'closed' ? 'Closed' : 'Needs review'}</Badge>
      </div>
      <p className="text-caption text-[var(--text-muted)]">Constrained Timeline context · Revision {item.revision}</p>
      <Link href={returnTo} className="inline-flex min-h-11 items-center text-sm font-medium text-[var(--primary)] underline underline-offset-4">Return to Review</Link>
    </header>
    <div className="space-y-4 p-4">
      {linkWasStale && <p role="status" className="border border-[var(--warning)] p-3 text-sm">The linked revision changed. This is the current result; no earlier decision can be resurrected.</p>}
      {message && <p role="status" className="text-sm">{message}</p>}
      <section className="space-y-2">
        <h3 className="text-sm font-medium">Non-authoritative candidate</h3>
        <p className="text-sm">One exact current reference resolves inside this Matter. It proposes only <span className="font-mono">refers_to</span>; wording does not infer a relationship type.</p>
        <ol className="space-y-2" aria-label="Candidate relationship endpoints">
          <li className="rounded-[var(--radius-sm)] border border-[var(--warning)] p-3 text-sm"><span className="text-caption text-[var(--text-muted)]">Source</span><span className="block break-words font-medium">{evidence.source_document_title}</span></li>
          <li className="rounded-[var(--radius-sm)] border border-[var(--warning)] p-3 text-sm"><span className="text-caption text-[var(--text-muted)]">Referenced target</span><span className="block break-words font-medium">{evidence.target_document_title}</span></li>
        </ol>
        <p className="text-sm">Candidate: {evidence.source_document_title} <span className="font-mono">refers_to</span> {evidence.target_document_title}</p>
        <p className="text-caption text-[var(--text-muted)]">Accepted <span className="font-mono">refers_to</span> is inspectable but is not a Timeline progression edge.</p>
      </section>
      <section className="space-y-2 border-t border-[var(--border)] pt-3">
        <h3 className="text-sm font-medium">Exact source evidence</h3>
        <blockquote className="break-words border-l-2 border-[var(--border-strong)] pl-3 text-sm text-[var(--text-secondary)]">“{item.evidence[0].quotation}”</blockquote>
        <p className="break-all font-mono text-caption">{evidence.identifier_kind} · {evidence.namespace} · {evidence.normalized_value}</p>
        <div className="flex flex-col items-start gap-1">
          <Link href={canonicalDocumentPath(evidence.source_document_id, { version: evidence.source_document_version_id, page: String(item.evidence[0].page_number) })} className="inline-flex min-h-11 items-center text-sm text-[var(--primary)] underline underline-offset-4">Open exact PDF source · Page {item.evidence[0].page_number}</Link>
          <Link href={canonicalDocumentPath(evidence.target_document_id, { version: evidence.target_document_version_id })} className="inline-flex min-h-11 items-center text-sm text-[var(--primary)] underline underline-offset-4">Inspect referenced document</Link>
        </div>
      </section>
      {item.status === 'closed' ? <section className="space-y-2 border-t border-[var(--border)] pt-3">
        <h3 className="text-sm font-medium">Current result</h3>
        <p className="text-sm">{outcome === 'reject_relationship' ? 'Suggestion rejected; no relationship was created.' : outcome === 'accept_relationship' ? 'The exact refers_to relationship was accepted. It remains inspectable and is not a Timeline progression edge.' : 'A human-corrected relationship was recorded.'}</p>
        {item.last_decision?.reason && <p className="break-words text-caption text-[var(--text-muted)]">Reason: {item.last_decision.reason}</p>}
      </section> : canResolve ? <fieldset className="space-y-3 border-t border-[var(--border)] pt-3">
        <legend className="text-sm font-medium">Decision</legend>
        {(['accept_relationship', 'correct_relationship', 'reject_relationship'] as const).map((value) => <label key={value} className="flex min-h-11 cursor-pointer items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border)] p-3">
          <input type="radio" name="timeline-relationship-decision" checked={action === value} onChange={() => setAction(value)} className="mt-1 size-4 accent-[var(--primary)]" />
          <span className="text-sm">{value === 'accept_relationship' ? 'Accept exact refers_to' : value === 'correct_relationship' ? 'Correct type or direction' : 'Reject suggestion'}</span>
        </label>)}
        {action === 'correct_relationship' && <div className="space-y-3 border-l-2 border-[var(--border-strong)] pl-3">
          <div><Label htmlFor="timeline-relationship-type">Current allowed relationship type</Label><select id="timeline-relationship-type" className="input-base min-h-11 w-full" value={relationshipType} onChange={(event) => setRelationshipType(event.target.value)}>{catalogue.map((entry) => <option key={`${entry.relationship_type}:${entry.catalogue_version}`} value={entry.relationship_type}>{entry.canonical_phrase}</option>)}</select></div>
          <label className="flex min-h-11 cursor-pointer items-center gap-3"><input type="checkbox" checked={reverse} onChange={(event) => setReverse(event.target.checked)} className="size-4 accent-[var(--primary)]" /><span className="text-sm">Reverse source and target</span></label>
          {selectedCatalogue && <p className="text-caption text-[var(--text-muted)]">{selectedCatalogue.timeline_visible ? 'This current catalogue type can appear as a Timeline progression edge.' : 'This type remains inspectable and is not a Timeline progression edge.'}</p>}
        </div>}
        <Button className="w-full" disabled={!action || pending || (action === 'correct_relationship' && !selectedCatalogue)} onClick={() => setConfirming(true)}>Review relationship decision</Button>
      </fieldset> : <p className="border-t border-[var(--border)] pt-3 text-sm text-[var(--text-muted)]">This current item is read-only or no longer eligible. No relationship can be changed here.</p>}
    </div>
    <Dialog open={confirming} onOpenChange={(open) => { if (!open && !pending) setConfirming(false) }}>
      <DialogContent>
        <DialogHeader><DialogTitle>{action === 'accept_relationship' ? 'Accept this exact reference?' : action === 'correct_relationship' ? 'Record the corrected relationship?' : 'Reject this suggestion?'}</DialogTitle><DialogDescription>{action === 'reject_relationship' ? 'This closes the candidate without creating a relationship.' : action === 'accept_relationship' ? 'This creates one inspectable refers_to relationship. It is not a Timeline progression edge.' : 'The current allowed type and chosen direction are rechecked atomically before activation.'}</DialogDescription></DialogHeader>
        <div className="space-y-2"><Label htmlFor="timeline-relationship-reason">Reason</Label><textarea id="timeline-relationship-reason" className="input-base min-h-24 max-h-40 resize-y" maxLength={500} value={reason} disabled={pending} onChange={(event) => setReason(event.target.value.replace(/[\r\n]/g, ' '))} /><p className="text-caption text-[var(--text-muted)]">Explain the decision. {reason.length}/500</p></div>
        <DialogFooter><Button variant="ghost" disabled={pending} onClick={() => setConfirming(false)}>Return to decision</Button><Button loading={pending} disabled={reason.trim().length < 2} onClick={submit}>{action === 'reject_relationship' ? 'Reject suggestion' : action === 'accept_relationship' ? 'Accept relationship' : 'Record correction'}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </aside>
}
