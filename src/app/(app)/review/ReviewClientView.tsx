'use client'

import { useEffect, useRef, useState, useTransition } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import Link from 'next/link'
import { formatDistanceStrict } from 'date-fns'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { DropdownMenu, DropdownMenuContent, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { canonicalDocumentPath } from '@/lib/canonical-document-route'
import { resolveExtractionConflict } from '@/lib/actions/review'
import { reviewFieldLabel, reviewValueLabel, taxPeriodComparison, type ReviewDetail, type ReviewFilters, type ReviewQueueItem, type ReviewResolution } from '@/lib/review/model'
import { cn } from '@/lib/utils'

type Queue = { items: ReviewQueueItem[]; totalCount: number; canResolve: boolean; authorised: boolean }
const statusLabel = (status: string) => status === 'closed' ? 'Closed' : 'Needs review'
const priorityLabel = (priority: string) => priority[0].toUpperCase() + priority.slice(1)
const age = (date: string, asOf: number) => formatDistanceStrict(new Date(date), new Date(asOf), { addSuffix: true })

function Filter({ label, value, options, onChange }: { label: string; value: string; options: [string, string][]; onChange: (value: string) => void }) {
  return <DropdownMenu><DropdownMenuTrigger asChild><Button size="sm" variant="ghost" aria-label={`Filter ${label}: ${options.find(option => option[0] === value)?.[1]}`}>{label}: {options.find(option => option[0] === value)?.[1]}</Button></DropdownMenuTrigger><DropdownMenuContent align="start"><DropdownMenuRadioGroup value={value} onValueChange={onChange}>{options.map(([id, text]) => <DropdownMenuRadioItem key={id} value={id}>{text}</DropdownMenuRadioItem>)}</DropdownMenuRadioGroup></DropdownMenuContent></DropdownMenu>
}

export function ReviewClientView({ queue, detail, filters, asOf }: { queue: Queue; detail: ReviewDetail | null; filters: ReviewFilters; asOf: number }) {
  const router = useRouter()
  const params = useSearchParams()
  const [pending, startTransition] = useTransition()
  const queueScroller = useRef<HTMLDivElement>(null)
  const savedScroll = useRef(0)
  const workspace = useRef<HTMLElement>(null)
  const originatingRow = useRef<HTMLButtonElement | null>(null)
  const focusDestination = useRef<'detail' | 'list' | null>(null)
  useEffect(() => {
    if (pending) return
    if (focusDestination.current === 'detail' && filters.item) {
      if (window.matchMedia('(max-width: 1279px)').matches) (workspace.current?.querySelector<HTMLElement>('#review-detail-heading') ?? workspace.current?.querySelector<HTMLElement>('[role="tab"][aria-selected="true"]'))?.focus({ preventScroll: true })
      focusDestination.current = null
    } else if (focusDestination.current === 'list' && !filters.item) {
      if (queueScroller.current) queueScroller.current.scrollTop = savedScroll.current
      originatingRow.current?.focus({ preventScroll: true })
      focusDestination.current = null
    }
  }, [filters.item, pending])
  function navigate(values: Record<string, string | undefined>) {
    if (pending) return
    if (values.item) { savedScroll.current = queueScroller.current?.scrollTop ?? 0; focusDestination.current = 'detail' }
    else if ('item' in values) focusDestination.current = 'list'
    const query = new URLSearchParams(params.toString())
    for (const [key, value] of Object.entries(values)) { if (value) query.set(key, value); else query.delete(key) }
    startTransition(() => router.push(`/review?${query}`, { scroll: false }))
  }
  const filterControls = <>
    <Filter label="Type" value={filters.type} options={[["all", "All"], ["extraction_conflict", "Extraction conflict"]]} onChange={type => navigate({ type, page: undefined })} />
    <Filter label="Priority" value={filters.priority} options={[["all", "All"], ["normal", "Normal"], ["high", "High"], ["urgent", "Urgent"]]} onChange={priority => navigate({ priority, page: undefined })} />
    <Filter label="Status" value={filters.status} options={[["needs_review", "Needs review"], ["closed", "Closed"], ["all", "All"]]} onChange={status => navigate({ status, page: undefined })} />
  </>
  if (!queue.authorised) return <div className="p-6"><h1 className="text-page-title">Review</h1><p>Your current organisation access does not include Review.</p></div>
  return <section ref={workspace} className="flex min-h-0 flex-1 flex-col overflow-hidden" aria-busy={pending}>
    <h1 className="mb-3 shrink-0 text-page-title">Review</h1>
    <div className="flex min-h-0 flex-1 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
      <section className={cn('min-h-0 min-w-0 flex-1 flex-col', filters.item ? 'hidden xl:flex xl:basis-3/5' : 'flex')} aria-label="Review queue">
        <div className="shrink-0 border-b border-[var(--border)] p-3">
          <form key={filters.search} className="flex min-w-0 flex-wrap items-end gap-2" onSubmit={event => { event.preventDefault(); navigate({ search: String(new FormData(event.currentTarget).get('search') ?? ''), page: undefined }) }}>
            <div className="min-w-0 flex-1"><Label htmlFor="review-search">Search Review</Label><Input id="review-search" name="search" maxLength={200} defaultValue={filters.search} placeholder="Document, Matter or field" /></div>
            <Button type="submit" variant="outline" disabled={pending}>Search</Button>
            <span className="w-full text-caption text-[var(--text-muted)]" role="status">{pending ? 'Loading Review…' : `${queue.totalCount} ${queue.totalCount === 1 ? 'item' : 'items'}`}</span>
          </form>
          <div className="mt-2 flex flex-wrap gap-1 lg:hidden">{filterControls}</div>
        </div>
        <div ref={queueScroller} data-review-list-scroller className="min-h-0 flex-1 overflow-y-auto overscroll-contain">
          <Table className="hidden lg:table">
            <TableCaption>Extraction conflicts requiring a decision</TableCaption>
            <TableHeader sticky><TableRow><TableHead>Decision</TableHead><TableHead><Filter label="Type" value={filters.type} options={[["all", "All"], ["extraction_conflict", "Extraction conflict"]]} onChange={type => navigate({ type, page: undefined })} /></TableHead><TableHead><Filter label="Priority" value={filters.priority} options={[["all", "All"], ["normal", "Normal"], ["high", "High"], ["urgent", "Urgent"]]} onChange={priority => navigate({ priority, page: undefined })} /></TableHead><TableHead><Filter label="Status" value={filters.status} options={[["needs_review", "Needs review"], ["closed", "Closed"], ["all", "All"]]} onChange={status => navigate({ status, page: undefined })} /></TableHead></TableRow></TableHeader>
            <TableBody>{queue.items.map(item => <TableRow key={item.id} selected={item.id === filters.item} className="h-14" interactive>
              <TableCell><Button variant="link" disabled={pending} className="max-w-full text-left" onClick={event => { originatingRow.current = event.currentTarget; navigate({ item: item.id, tab: 'evidence' }) }}><span className="min-w-0"><span className="block">Review {reviewFieldLabel(item.field_path)}</span><span className="block max-w-64 truncate text-caption text-[var(--text-muted)]" title={`${item.document_title} · ${item.matter_title}`}>{item.document_title || 'Document'} · {item.matter_title}</span></span></Button></TableCell>
              <TableCell><span className="text-xs">Extraction conflict</span><p className="text-caption text-[var(--text-muted)]">{age(item.created_at, asOf)}</p></TableCell>
              <TableCell><span title={item.priority_reason} aria-label={`${priorityLabel(item.priority)} priority: ${item.priority_reason}`}>{priorityLabel(item.priority)}</span></TableCell>
              <TableCell><Badge variant={item.status === 'closed' ? 'muted' : 'warning'} fixedWidth="lg">{statusLabel(item.status)}</Badge></TableCell>
            </TableRow>)}</TableBody>
          </Table>
          <div className="divide-y divide-[var(--border)] lg:hidden">{queue.items.map(item => <div key={item.id} className="space-y-2 p-3">
            <Button variant="link" disabled={pending} className="text-left" onClick={event => { originatingRow.current = event.currentTarget; navigate({ item: item.id, tab: 'evidence' }) }}>Review {reviewFieldLabel(item.field_path)}</Button>
            <p className="break-words text-sm">{item.document_title || 'Document'}</p><p className="break-words text-caption text-[var(--text-muted)]">{item.client_name} · {item.matter_title}</p>
            <div className="flex flex-wrap items-center gap-2"><Badge variant={item.status === 'closed' ? 'muted' : 'warning'} fixedWidth="lg">{statusLabel(item.status)}</Badge><span className="text-caption">Extraction conflict · {priorityLabel(item.priority)} · {age(item.created_at, asOf)}</span></div>
          </div>)}</div>
          {queue.items.length === 0 && <div className="px-6 py-16 text-center"><h2 className="text-section-heading">{queue.totalCount ? 'No items on this page' : 'No Review items found'}</h2><p className="mt-2 text-sm text-[var(--text-muted)]">{filters.search || filters.status !== 'needs_review' || filters.priority !== 'all' ? 'Try changing your search or filters.' : 'Current extraction conflicts will appear here when a decision is needed.'}</p></div>}
        </div>
        <footer className="flex shrink-0 flex-wrap items-center justify-between gap-2 border-t border-[var(--border)] p-3 text-caption"><span>Page {filters.page} of {Math.max(1, Math.ceil(queue.totalCount / 25))}</span><div className="flex gap-2"><Button size="sm" variant="outline" disabled={filters.page <= 1 || pending} onClick={() => navigate({ page: String(filters.page - 1) })}>Previous</Button><Button size="sm" variant="outline" disabled={filters.page * 25 >= queue.totalCount || pending} onClick={() => navigate({ page: String(filters.page + 1) })}>Next</Button></div></footer>
      </section>
      {filters.item && <aside className="flex min-h-0 min-w-0 flex-1 flex-col xl:basis-2/5 xl:border-l xl:border-[var(--border)]" aria-label="Selected Review item">
        <div className="flex shrink-0 items-center justify-between gap-1 border-b border-[var(--border)] p-2"><div className="flex gap-1" role="tablist" aria-label="Review detail">{(['evidence', 'decision'] as const).map(tab => <Button key={tab} id={`review-tab-${tab}`} role="tab" aria-selected={filters.tab === tab} aria-controls="review-tabpanel" tabIndex={filters.tab === tab ? 0 : -1} variant={filters.tab === tab ? 'secondary' : 'ghost'} onKeyDown={event => {
          if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return
          event.preventDefault()
          const next = event.key === 'Home' ? 'evidence' : event.key === 'End' ? 'decision' : tab === 'evidence' ? 'decision' : 'evidence'
          workspace.current?.querySelector<HTMLButtonElement>(`#review-tab-${next}`)?.focus()
          navigate({ tab: next })
        }} onClick={() => navigate({ tab })}>{tab === 'evidence' ? 'Evidence' : 'Decision'}</Button>)}</div><Button variant="ghost" size="sm" onClick={() => navigate({ item: undefined, tab: undefined })}>Back to list</Button></div>
        {detail ? <ReviewItemDetail key={`${detail.id}:${detail.revision}`} detail={detail} asOf={asOf} tab={filters.tab} onDecisionTab={() => navigate({ tab: 'decision' })} /> : <div id="review-tabpanel" role="tabpanel" aria-labelledby={`review-tab-${filters.tab}`} tabIndex={0}><p className="p-6" role="status">This Review item is no longer available.</p></div>}
      </aside>}
    </div>
  </section>
}

function ReviewItemDetail({ detail, tab, onDecisionTab, asOf }: { detail: ReviewDetail; tab: ReviewFilters['tab']; onDecisionTab: () => void; asOf: number }) {
  const [item, setItem] = useState(detail)
  const [choice, setChoice] = useState('')
  const [reason, setReason] = useState('')
  const [confirmation, setConfirmation] = useState<ReviewResolution | null>(null)
  const [message, setMessage] = useState('')
  const [pending, startTransition] = useTransition()
  const router = useRouter()
  const selected = item.evidence.find(evidence => evidence.candidate_id === choice)
  const canResolve = item.allowed_actions.length > 0
  function confirm() {
    if (!confirmation) return
    startTransition(async () => {
      try {
        const result = await resolveExtractionConflict(confirmation)
        setMessage(result.message)
        if (result.item) setItem(result.item)
        if (result.code !== 'failed') { setConfirmation(null); setChoice(''); setReason(''); router.refresh() }
      } catch { setMessage('The decision could not be recorded. Retry this confirmation.') }
    })
  }
  return <>
    <header className="shrink-0 space-y-2 border-b border-[var(--border)] p-4">
      <h2 id="review-detail-heading" tabIndex={-1} className="break-words text-section-heading">Review {reviewFieldLabel(item.field_path)}</h2>
      <p className="line-clamp-2 break-words text-sm" title={item.document_title || 'Document'}>{item.document_title || 'Document'}</p>
      <div className="flex flex-wrap items-center gap-2 text-caption"><Badge variant={item.status === 'closed' ? 'muted' : 'warning'} fixedWidth="lg">{statusLabel(item.status)}</Badge><span>Extraction conflict</span></div>
      <p className="text-caption text-[var(--text-muted)]"><span title={item.priority_reason} aria-label={`${priorityLabel(item.priority)} priority: ${item.priority_reason}`}>{priorityLabel(item.priority)} priority</span> · {age(item.created_at, asOf)}</p>
    </header>
    <div key={tab} id="review-tabpanel" role="tabpanel" aria-labelledby={`review-tab-${tab}`} tabIndex={0} className="min-h-0 flex-1 space-y-5 overflow-y-auto overscroll-contain p-4">
      {message && <p role="status" className="text-sm">{message}</p>}
      {item.closure_reason === 'source_replaced' && <p className="text-sm">The source or its candidate evidence was replaced. This item is closed; it cannot change the current document.</p>}
      {tab === 'evidence' ? <>
        <p className="break-words text-caption text-[var(--text-muted)]">{item.client_name} · {item.matter_title} · Document version {item.version_number}{!item.is_current && ' (historical)'}</p>
        {item.record_baseline && <section className="space-y-2 border-t border-[var(--border)] pt-3">
          <h3 className="text-sm font-medium">Record value before PDF attachment</h3>
          <p className="break-words text-sm">{item.record_baseline.value}</p>
          <p className="text-caption text-[var(--text-muted)]">Preserved from the document record, not extracted from this PDF. This value is context for clarification, not selectable PDF evidence.</p>
        </section>}
        {item.evidence.map(evidence => {
          const comparison = taxPeriodComparison(evidence.value)
          return <section key={evidence.candidate_id} className="space-y-2 border-t border-[var(--border)] pt-3">
            <h3 className="text-sm font-medium">Evidence {evidence.ordinal} · Page {evidence.page_number}</h3>
            <p className="break-words text-sm">{reviewValueLabel(evidence.value)}</p>
            <blockquote className="break-words border-l-2 border-[var(--border-strong)] pl-3 text-sm text-[var(--text-secondary)]">“{evidence.quotation}”</blockquote>
            {comparison && <div className="text-sm"><p>Printed financial years: {comparison.printed}</p><p>Derived comparison: {comparison.derived}</p></div>}
            <Link className="inline-flex min-h-11 items-center text-sm text-[var(--primary)] underline underline-offset-4" href={canonicalDocumentPath(item.document_id, { version: item.document_version_id, page: String(evidence.page_number) })}>Open exact source · Page {evidence.page_number}</Link>
            {!evidence.selectable && <p className="text-caption text-[var(--text-muted)]">{evidence.validation_state === 'invalid' ? 'This observation failed validation and cannot be selected.' : 'This evidence does not independently resolve the conflict.'}</p>}
          </section>
        })}
      </> : <>
        <p className="text-sm">{item.impact}</p>
        {item.last_decision && <section className="space-y-2"><h3 className="text-sm font-medium">{item.last_decision.action === 'select_candidate' ? 'Recorded outcome' : 'Clarification requested'}</h3>{item.last_decision.selected_candidate_id && <p className="break-words text-sm">Selected: {reviewValueLabel(item.evidence.find(e => e.candidate_id === item.last_decision?.selected_candidate_id)?.value)}</p>}<p className="break-words text-sm">{item.last_decision.reason}</p></section>}
        {canResolve ? <fieldset className="space-y-3"><legend className="mb-3 text-sm font-medium">Choose an outcome</legend>
          {item.allowed_actions.includes('select_candidate') && item.evidence.filter(evidence => evidence.selectable).map(evidence => <label key={evidence.candidate_id} className="flex min-h-11 cursor-pointer items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border)] p-3"><input type="radio" name="review-outcome" className="mt-1 size-4 shrink-0 accent-[var(--primary)]" checked={choice === evidence.candidate_id} onChange={() => setChoice(evidence.candidate_id)} /><span className="min-w-0 break-words text-sm">Use {reviewValueLabel(evidence.value)}<span className="mt-1 block text-caption text-[var(--text-muted)]">Accept evidence {evidence.ordinal}; reject competing item candidates and close Review.</span></span></label>)}
          <label className="flex min-h-11 cursor-pointer items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border)] p-3"><input type="radio" name="review-outcome" className="mt-1 size-4 shrink-0 accent-[var(--primary)]" checked={choice === 'clarify'} onChange={() => setChoice('clarify')} /><span className="text-sm">Request clarification<span className="mt-1 block text-caption text-[var(--text-muted)]">Record what needs clarification. Keep this item in Needs review.</span></span></label>
          {!item.allowed_actions.includes('select_candidate') && <p className="text-sm text-[var(--text-muted)]">No supported candidate can resolve this conflict. Describe the clarification needed.</p>}
        </fieldset> : item.status !== 'closed' && <p className="text-sm text-[var(--text-muted)]">Read-only access. An authorised team member can record a decision.</p>}
      </>}
    </div>
    <footer className="shrink-0 border-t border-[var(--border)] p-3">
      {tab === 'evidence' ? <Button variant="outline" className="w-full" onClick={onDecisionTab}>View decision</Button> : canResolve ? <Button className="w-full" disabled={!choice || pending} onClick={() => setConfirmation({ itemId: item.id, revision: item.revision, action: choice === 'clarify' ? 'request_clarification' : 'select_candidate', candidateId: selected?.candidate_id ?? null, reason: '', idempotencyKey: crypto.randomUUID() })}>Review decision</Button> : <p className="text-caption text-[var(--text-muted)]">{item.status === 'closed' ? 'This Review item is closed.' : 'No decision actions available.'}</p>}
    </footer>
    <Dialog open={confirmation !== null} onOpenChange={open => { if (!open && !pending) { setConfirmation(null); setReason('') } }}><DialogContent><DialogHeader><DialogTitle>{confirmation?.action === 'select_candidate' ? 'Use this extracted value?' : 'Request clarification?'}</DialogTitle><DialogDescription>{confirmation?.action === 'select_candidate' ? `Use ${reviewValueLabel(selected?.value)}. Competing item candidates will be rejected and this Review item will close.` : 'Record what needs clarification. The current value stays unchanged and this item remains in Needs review.'}</DialogDescription></DialogHeader>
      <div className="min-w-0 space-y-2"><Label htmlFor="review-reason">Reason</Label><textarea id="review-reason" className="input-base min-h-24 max-h-40 resize-y" rows={4} value={reason} maxLength={500} disabled={pending} onChange={event => { const next = event.target.value.replace(/[\r\n]/g, ' '); setReason(next); setConfirmation(value => value && { ...value, reason: next }) }} aria-describedby="review-reason-help" /><p id="review-reason-help" className="text-caption text-[var(--text-muted)]">Explain the decision in up to 500 characters. {reason.length}/500</p>{message && <p role="status" className="text-sm">{message}</p>}</div>
      <DialogFooter><Button variant="ghost" disabled={pending} onClick={() => { setConfirmation(null); setReason('') }}>Return to decision</Button><Button loading={pending} disabled={!reason.trim()} onClick={confirm}>{confirmation?.action === 'select_candidate' ? 'Confirm selected value' : 'Request clarification'}</Button></DialogFooter>
    </DialogContent></Dialog>
  </>
}
