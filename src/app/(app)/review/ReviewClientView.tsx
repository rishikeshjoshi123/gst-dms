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
import { getIntakeItemSignedUrl } from '@/lib/actions/document'
import { continueProcessingManually, previewMultiPlacementConflictMove, previewPlacementConflictMove, resolveAmbiguousPlacement, resolveExplicitDueDate, resolveExtractionConflict, resolveMultiPlacementConflict, resolvePlacementConflict } from '@/lib/actions/review'
import { reviewFieldLabel, reviewValueLabel, taxPeriodComparison, type AmbiguousPlacementResolution, type DeadlineReviewResolution, type ExtractionReviewResolution, type MultiPlacementConflictResolution, type PlacementConflictResolution, type ProcessingRecoveryResolution, type ReviewDetail, type ReviewFilters, type ReviewQueueItem } from '@/lib/review/model'
import { currentMultiPreview, hasCurrentMultiMoveImpact, isCurrentMultiPreviewTicket, nextMultiPreviewTicket } from '@/lib/review/multi-preview-fence'
import { cn } from '@/lib/utils'

type Queue = { items: ReviewQueueItem[]; totalCount: number; canResolve: boolean; authorised: boolean }
const statusLabel = (status: string) => status === 'closed' ? 'Closed' : 'Needs review'
const priorityLabel = (priority: string) => priority[0].toUpperCase() + priority.slice(1)
const age = (date: string, asOf: number) => formatDistanceStrict(new Date(date), new Date(asOf), { addSuffix: true })
const typeLabel = (type: ReviewQueueItem['type']) => type === 'processing_recovery' ? 'Processing recovery' : type === 'ambiguous_placement' ? 'Intake placement conflict' : type === 'placement_conflict' ? 'Filed document placement conflict' : type === 'multi_placement_conflict' ? 'Multiple filed Matter conflicts' : type === 'deadline_verification' ? 'Legal date verification' : 'Extraction conflict'
const itemLabel = (item: ReviewQueueItem | ReviewDetail) => item.type === 'processing_recovery' ? 'Continue document manually' : item.type === 'ambiguous_placement' ? 'Choose a Matter destination' : item.type === 'placement_conflict' || item.type === 'multi_placement_conflict' ? 'Review current filing' : item.type === 'deadline_verification' ? 'Review proposed legal date' : `Review ${reviewFieldLabel(item.field_path)}`
type MultiCandidateValue={target_matter_id:string;target_matter_title:string;target_matter_code:string;target_client_name:string;target_identifier_id:string;target_identifier_revision:number;kind:string;namespace:string;normalized_value:string;display:string;verified_at:string;source_candidate_id:string;source_analysis_run_id:string}
function multiCandidateValue(value:unknown):MultiCandidateValue|null{
  if(!value||typeof value!=='object'||Array.isArray(value)) return null
  const fact=value as Record<string,unknown>
  return typeof fact.target_matter_id==='string'&&typeof fact.target_matter_title==='string'&&typeof fact.display==='string' ? fact as MultiCandidateValue : null
}
type PlacementValue = { matter_id: string; matter_title: string; matter_code: string | null; client_name: string; evidence: { kind: string; source_page_number: number | null }[] }
function placementValue(value: unknown): PlacementValue | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const candidate = value as Partial<PlacementValue>
  return typeof candidate.matter_id === 'string' && typeof candidate.matter_title === 'string' && typeof candidate.client_name === 'string' && Array.isArray(candidate.evidence) ? candidate as PlacementValue : null
}
const evidenceLabel = (kind: string) => ({ matter_code_exact: 'Exact Matter code', external_proceeding_id_exact: 'Exact verified proceeding identifier', referenced_document_exact: 'Exact referenced document', verified_client_identifier: 'Verified client identifier agrees', tax_period_overlap: 'Tax period overlaps', procedure_compatible: 'Procedure is compatible' }[kind] ?? 'Trusted placement evidence')

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
    <Filter label="Type" value={filters.type} options={[["all", "All"], ["extraction_conflict", "Extraction conflict"], ["processing_recovery", "Processing recovery"], ["ambiguous_placement", "Intake placement conflict"], ["placement_conflict", "Filed placement conflict"], ["multi_placement_conflict", "Multiple filed conflicts"], ["deadline_verification", "Legal date verification"]]} onChange={type => navigate({ type, page: undefined })} />
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
            <TableCaption>Review items requiring a typed decision</TableCaption>
            <TableHeader sticky><TableRow><TableHead>Decision</TableHead><TableHead><Filter label="Type" value={filters.type} options={[["all", "All"], ["extraction_conflict", "Extraction conflict"], ["processing_recovery", "Processing recovery"], ["ambiguous_placement", "Intake placement conflict"], ["placement_conflict", "Filed placement conflict"], ["multi_placement_conflict", "Multiple filed conflicts"], ["deadline_verification", "Legal date verification"]]} onChange={type => navigate({ type, page: undefined })} /></TableHead><TableHead><Filter label="Priority" value={filters.priority} options={[["all", "All"], ["normal", "Normal"], ["high", "High"], ["urgent", "Urgent"]]} onChange={priority => navigate({ priority, page: undefined })} /></TableHead><TableHead><Filter label="Status" value={filters.status} options={[["needs_review", "Needs review"], ["closed", "Closed"], ["all", "All"]]} onChange={status => navigate({ status, page: undefined })} /></TableHead></TableRow></TableHeader>
            <TableBody>{queue.items.map(item => <TableRow key={item.id} selected={item.id === filters.item} className="h-14" interactive>
              <TableCell><Button variant="link" disabled={pending} className="max-w-full text-left" onClick={event => { originatingRow.current = event.currentTarget; navigate({ item: item.id, tab: 'evidence' }) }}><span className="min-w-0"><span className="block">{itemLabel(item)}</span><span className="block max-w-64 truncate text-caption text-[var(--text-muted)]" title={`${item.document_title} · ${item.matter_title}`}>{item.document_title || 'Document'} · {item.matter_title}</span></span></Button></TableCell>
              <TableCell><span className="text-xs">{typeLabel(item.type)}</span><p className="text-caption text-[var(--text-muted)]">{age(item.created_at, asOf)}</p></TableCell>
              <TableCell><span title={item.priority_reason} aria-label={`${priorityLabel(item.priority)} priority: ${item.priority_reason}`}>{priorityLabel(item.priority)}</span></TableCell>
              <TableCell><Badge variant={item.status === 'closed' ? 'muted' : 'warning'} fixedWidth="lg">{statusLabel(item.status)}</Badge></TableCell>
            </TableRow>)}</TableBody>
          </Table>
          <div className="divide-y divide-[var(--border)] lg:hidden">{queue.items.map(item => <div key={item.id} className="space-y-2 p-3">
            <Button variant="link" disabled={pending} className="text-left" onClick={event => { originatingRow.current = event.currentTarget; navigate({ item: item.id, tab: 'evidence' }) }}>{itemLabel(item)}</Button>
            <p className="break-words text-sm">{item.document_title || 'Document'}</p><p className="break-words text-caption text-[var(--text-muted)]">{item.client_name} · {item.matter_title}</p>
            <div className="flex flex-wrap items-center gap-2"><Badge variant={item.status === 'closed' ? 'muted' : 'warning'} fixedWidth="lg">{statusLabel(item.status)}</Badge><span className="text-caption">{typeLabel(item.type)} · {priorityLabel(item.priority)} · {age(item.created_at, asOf)}</span></div>
          </div>)}</div>
          {queue.items.length === 0 && <div className="px-6 py-16 text-center"><h2 className="text-section-heading">{queue.totalCount ? 'No items on this page' : 'No Review items found'}</h2><p className="mt-2 text-sm text-[var(--text-muted)]">{filters.search || filters.status !== 'needs_review' || filters.priority !== 'all' ? 'Try changing your search or filters.' : 'Current extraction conflicts and processing recovery work will appear here.'}</p></div>}
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
  const [correctedDate, setCorrectedDate] = useState('')
  const [reason, setReason] = useState('')
  const [manual, setManual] = useState({ doc_type: 'OTHER', reference_number: '', document_date: '', direction: 'incoming', issued_by: '' })
  const [confirmation, setConfirmation] = useState<ExtractionReviewResolution | ProcessingRecoveryResolution | AmbiguousPlacementResolution | DeadlineReviewResolution | PlacementConflictResolution | MultiPlacementConflictResolution | null>(null)
  const [movePreview, setMovePreview] = useState<{code:string;fingerprint?:string;blockers?:string[];categories?:{key:string;label:string;count:number}[];sourceMatterTitle?:string;targetMatterTitle?:string;documentTitle?:string}|null>(null)
  const [multiMovePreview,setMultiMovePreview]=useState<{itemId:string;targetMatterId:string;preview:{code:string;fingerprint?:string;blockers?:string[];categories?:{key:string;label:string;count:number}[];sourceMatterTitle?:string;targetMatterTitle?:string;documentTitle?:string}}|null>(null)
  const latestMultiPreviewRequest=useRef({sequence:0,itemId:detail.id,targetMatterId:null as string|null})
  const [previewPending, setPreviewPending] = useState(false)
  const [message, setMessage] = useState('')
  const [pending, startTransition] = useTransition()
  const router = useRouter()
  const selected = item.evidence.find(evidence => evidence.candidate_id === choice)
  const selectedMultiPreview=currentMultiPreview(multiMovePreview,item.id,choice)
  const canResolve = item.allowed_actions.length > 0
  const recordedSource = `${item.matter_title}${item.old_matter_code ? ` (${item.old_matter_code})` : ''}`
  const recordedTarget = `${item.target_matter_title ?? 'verified target'}${item.target_matter_code ? ` (${item.target_matter_code})` : ''}`
  const currentFiling = item.current_matter_title
    ? `${item.current_matter_title}${item.current_matter_code ? ` (${item.current_matter_code})` : ''}` : null
  const recordedPlacementAction = item.type==='placement_conflict' && item.closure_reason==='decision_recorded'
    ? item.last_decision?.action : null
  async function choosePlacement(action:'keep'|'move'){
    setChoice(action);setMovePreview(null)
    if(action==='move'){
      setPreviewPending(true)
      try { const preview=await previewPlacementConflictMove(item.id);setMovePreview(preview)
        if(preview.code!=='ok') setMessage('Current Move impact is unavailable. Refresh Review before deciding.')
      } catch { setMessage('Current Move impact could not be loaded.') }
      finally { setPreviewPending(false) }
    }
  }
  async function chooseMultiPlacement(targetMatterId:string|null){
    const itemId=item.id
    const ticket=nextMultiPreviewTicket(latestMultiPreviewRequest.current,itemId,targetMatterId)
    latestMultiPreviewRequest.current=ticket
    setChoice(targetMatterId??'keep');setMultiMovePreview(null);setMessage('')
    if(targetMatterId){
      setPreviewPending(true)
      const current=()=>isCurrentMultiPreviewTicket(latestMultiPreviewRequest.current,ticket)
      try{const preview=await previewMultiPlacementConflictMove(itemId,targetMatterId)
        if(!current()) return
        setMultiMovePreview({itemId,targetMatterId,preview})
        if(preview.code!=='ok') setMessage('This target’s current Move impact is unavailable. Refresh Review before deciding.')
      }catch{if(current()) setMessage('This target’s Move impact could not be loaded.')}
      finally{if(current()) setPreviewPending(false)}
    }else setPreviewPending(false)
  }
  function confirm() {
    if (!confirmation) return
    startTransition(async () => {
      try {
        if ((confirmation.action==='keep' || confirmation.action==='move') && 'targetMatterId' in confirmation){
          const result=await resolveMultiPlacementConflict(confirmation)
          setMessage(result.message)
          if(result.item) setItem(result.item)
          if(result.code!=='failed'){
            latestMultiPreviewRequest.current.sequence+=1
            latestMultiPreviewRequest.current.targetMatterId=null
            setConfirmation(null);setChoice('');setMultiMovePreview(null);setPreviewPending(false);setReason('');router.refresh()
          }
          return
        }
        if (confirmation.action==='keep' || confirmation.action==='move'){
          const result=await resolvePlacementConflict(confirmation as PlacementConflictResolution)
          setMessage(result.message)
          if(result.item) setItem(result.item)
          if(result.code!=='failed') {setConfirmation(null);setChoice('');setMovePreview(null);setReason('');router.refresh()}
          return
        }
        if (['verify','correct','reject','clear'].includes(confirmation.action)) {
          const result=await resolveExplicitDueDate(confirmation as DeadlineReviewResolution)
          setMessage(result.message)
          if(result.item) setItem(result.item)
          if(result.code!=='failed'){setConfirmation(null);setChoice('');setReason('');router.refresh()}
          return
        }
        if (confirmation.action === 'select_destination') {
          const result = await resolveAmbiguousPlacement(confirmation)
          setMessage(result.message)
          if (result.item) setItem(result.item)
          if (result.code === 'ok' && result.documentId && result.documentVersionId) {
            router.push(canonicalDocumentPath(result.documentId, { version: result.documentVersionId, page: '1' }))
            return
          }
          if (result.code !== 'failed') { setConfirmation(null); setChoice(''); setReason(''); router.refresh() }
          return
        }
        const result = confirmation.action === 'continue_manual'
          ? await continueProcessingManually(confirmation)
          : await resolveExtractionConflict(confirmation as ExtractionReviewResolution)
        setMessage(result.message)
        if (result.item) setItem(result.item)
        if (result.code !== 'failed') { setConfirmation(null); setChoice(''); setReason(''); router.refresh() }
      } catch { setMessage('The decision could not be recorded. Retry this confirmation.') }
    })
  }
  return <>
    <header className="shrink-0 space-y-2 border-b border-[var(--border)] p-4">
      <h2 id="review-detail-heading" tabIndex={-1} className="break-words text-section-heading">{itemLabel(item)}</h2>
      <p className="line-clamp-2 break-words text-sm" title={item.document_title || 'Document'}>{item.document_title || 'Document'}</p>
      <div className="flex flex-wrap items-center gap-2 text-caption"><Badge variant={item.status === 'closed' ? 'muted' : 'warning'} fixedWidth="lg">{statusLabel(item.status)}</Badge><span>{typeLabel(item.type)}</span></div>
      <p className="text-caption text-[var(--text-muted)]"><span title={item.priority_reason} aria-label={`${priorityLabel(item.priority)} priority: ${item.priority_reason}`}>{priorityLabel(item.priority)} priority</span> · {age(item.created_at, asOf)}</p>
    </header>
    <div key={tab} id="review-tabpanel" role="tabpanel" aria-labelledby={`review-tab-${tab}`} tabIndex={0} className="min-h-0 flex-1 space-y-5 overflow-y-auto overscroll-contain p-4">
      {message && <p role="status" className="text-sm">{message}</p>}
      {item.closure_reason === 'source_replaced' && <p className="text-sm">The source or its candidate evidence was replaced. This item is closed; it cannot change the current document.</p>}
      {item.closure_reason === 'source_unavailable' && <p className="text-sm">The Intake source or an eligible destination changed and is no longer available for this decision. This item is closed and no longer blocks Intake assignment.</p>}
      {tab === 'evidence' ? <>
        <p className="break-words text-caption text-[var(--text-muted)]">{item.type==='placement_conflict'||item.type==='multi_placement_conflict' ? 'Recorded source: ' : ''}{item.client_name} · {item.matter_title}{item.version_number !== null && <> · Document version {item.version_number}{!item.is_current && ' (historical)'}</>}</p>
        {item.type==='multi_placement_conflict' && <section className="space-y-3 border-t border-[var(--border)] pt-3">
          <h3 className="text-sm font-medium">Printed sources and verified Matter candidates</h3>
          <p className="break-words text-sm">{item.status==='needs_review'&&item.conflict_current
            ? `Currently filed in ${currentFiling??recordedSource}. This PDF has not moved.`
            : `Historical filing snapshot: ${recordedSource}. ${currentFiling?`Live current filing: ${currentFiling}.`:'Current filing is unavailable.'}`}</p>
          <p className="text-caption text-[var(--text-muted)]">Each printed observation is source-grounded but provisional. The keys below were separately human-verified on their target Matters. No candidate is selected automatically.</p>
          {item.evidence.map(candidate=>{const value=multiCandidateValue(candidate.value);return value&&<article key={candidate.candidate_id} className="space-y-2 rounded-[var(--radius-sm)] border border-[var(--border)] p-3">
            <h4 className="break-words text-sm font-medium">{value.target_matter_title} ({value.target_matter_code}) · {value.target_client_name}</h4>
            <p className="break-words font-mono text-caption">Matter ID {value.target_matter_id} · Verified key ID {value.target_identifier_id} · Revision {value.target_identifier_revision}</p>
            <blockquote className="break-words border-l-2 border-[var(--border-strong)] pl-3 text-sm text-[var(--text-secondary)]">“{candidate.quotation}”</blockquote>
            <Link className="inline-flex min-h-11 items-center text-sm text-[var(--primary)] underline underline-offset-4" href={canonicalDocumentPath(item.document_id,{version:item.document_version_id,page:String(candidate.page_number)})}>Open exact source · Page {candidate.page_number}</Link>
            <p className="break-words text-sm">Printed {value.kind.replaceAll('_',' ')} · {value.namespace} · {value.normalized_value}. Verified Matter key: {value.display} · verified {new Date(value.verified_at).toLocaleDateString()}.</p>
          </article>})}
        </section>}
        {item.type==='placement_conflict' && <section className="space-y-3 border-t border-[var(--border)] pt-3">
          <h3 className="text-sm font-medium">Printed source and verified destination</h3>
          <p className="break-words text-sm">{recordedPlacementAction==='move'
            ? `Recorded Move: ${recordedSource} → ${recordedTarget}. ${currentFiling ? `Current filing: ${currentFiling}.` : 'Current filing is unavailable.'}`
            : recordedPlacementAction==='keep'
              ? `Recorded Keep: ${recordedSource} was retained. ${currentFiling ? `Current filing: ${currentFiling}.` : 'Current filing is unavailable.'}`
              : item.status==='needs_review' && item.conflict_current
                ? `Currently filed in ${currentFiling ?? recordedSource}. The PDF has not moved for this Review.`
                : `Historical filing snapshot: ${recordedSource}. This Review did not decide a Move. ${currentFiling ? `Live current filing: ${currentFiling}.` : 'The current filing is unavailable.'}`}</p>
          <blockquote className="break-words border-l-2 border-[var(--border-strong)] pl-3 text-sm text-[var(--text-secondary)]">“{item.source_quote}”</blockquote>
          <Link className="inline-flex min-h-11 items-center text-sm text-[var(--primary)] underline underline-offset-4" href={canonicalDocumentPath(item.document_id,{version:item.document_version_id,page:String(item.source_page_number)})}>Open exact source · Page {item.source_page_number}</Link>
          <p className="break-words text-sm">Printed candidate: {item.identifier_kind?.replaceAll('_',' ')} · {item.issuer_namespace_normalized} · {item.normalized_value}. This PDF observation is source-grounded, not itself a human verification.</p>
          <p className="break-words text-sm">Verified Matter key: {item.display_value} · {item.target_matter_title} ({item.target_matter_code}) · {item.target_client_name}. Verified {item.target_verified_at ? new Date(item.target_verified_at).toLocaleDateString() : 'previously'}.</p>
          <p className="text-caption text-[var(--text-muted)]">{item.status==='needs_review' ? 'A verified key contradicts the current filing. Keep or Move is a human decision; source bytes and version remain exact.' : 'This is a recorded source and key snapshot. Its exact PDF version remains available through the source link.'}</p>
        </section>}
        {item.type === 'deadline_verification' && <section className="space-y-3 border-t border-[var(--border)] pt-3">
          <h3 className="text-sm font-medium">Source-stated date · Page {item.evidence[0]?.page_number}</h3>
          <p className="break-words text-sm">Proposed {item.candidate_due_date}. This is provisional; only a human decision activates a verified legal date. No type, statutory calculation or reminder has been inferred.</p>
          <blockquote className="break-words border-l-2 border-[var(--border-strong)] pl-3 text-sm text-[var(--text-secondary)]">“{item.evidence[0]?.quotation}”</blockquote>
          {item.evidence[0] && <Link className="inline-flex min-h-11 items-center text-sm text-[var(--primary)] underline" href={canonicalDocumentPath(item.document_id,{version:item.document_version_id,page:String(item.evidence[0].page_number)})}>Open exact source · Page {item.evidence[0].page_number}</Link>}
        </section>}
        {item.type === 'ambiguous_placement' && <section className="space-y-3 border-t border-[var(--border)] pt-3">
          <h3 className="text-sm font-medium">Placement evidence</h3>
          <p className="break-words text-sm">{item.impact}</p>
          <Button variant="outline" onClick={async () => { const result = await getIntakeItemSignedUrl(item.intake_id); if ('url' in result) window.location.assign(`${result.url}#page=1`); else setMessage(result.error || 'The Intake PDF could not be opened.') }}>Open exact Intake source · Page 1</Button>
          {item.evidence.map(candidate => { const value = placementValue(candidate.value); return value && <article key={candidate.candidate_id} className="rounded-[var(--radius-sm)] border border-[var(--border)] p-3">
            <h4 className="break-words text-sm font-medium">{value.matter_title}</h4><p className="mt-1 break-words text-caption text-[var(--text-muted)]">{value.client_name}{value.matter_code ? ` · ${value.matter_code}` : ''}</p>
            <ul className="mt-2 space-y-1 text-sm">{value.evidence.map((fact, index) => <li key={`${fact.kind}:${index}`}>{evidenceLabel(fact.kind)}{fact.source_page_number ? ` · Page ${fact.source_page_number}` : ''}</li>)}</ul>
          </article> })}
        </section>}
        {item.type === 'processing_recovery' && <section className="space-y-3 border-t border-[var(--border)] pt-3">
          <h3 className="text-sm font-medium">Automated extraction stopped</h3>
          <p className="break-words text-sm">{item.impact}</p>
          <p className="text-caption text-[var(--text-muted)]">Reason: {item.reason_code === 'provider_failed' ? 'Provider unavailable' : item.reason_code === 'invalid_model_output' ? 'Model output invalid' : 'Domain validation required'}. No provider response is shown or retained in this Review view.</p>
          <Link className="inline-flex min-h-11 items-center text-sm text-[var(--primary)] underline underline-offset-4" href={canonicalDocumentPath(item.document_id, { version: item.document_version_id, page: String(item.source_page_number) })}>Open exact source · Page {item.source_page_number}</Link>
        </section>}
        {item.record_baseline && <section className="space-y-2 border-t border-[var(--border)] pt-3">
          <h3 className="text-sm font-medium">Record value before PDF attachment</h3>
          <p className="break-words text-sm">{item.record_baseline.value}</p>
          <p className="text-caption text-[var(--text-muted)]">Preserved from the document record, not extracted from this PDF. This value is context for clarification, not selectable PDF evidence.</p>
        </section>}
        {item.type === 'extraction_conflict' && item.evidence.map(evidence => {
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
        {item.type==='deadline_verification' && item.decision_history && item.decision_history.length>0 && <section><h3 className="text-sm font-medium">Date decisions</h3><ol className="mt-2 space-y-2">{item.decision_history.map((decision,index)=><li key={index} className="break-words text-sm">{decision.action} {decision.due_date??'without activation'} · {decision.reason}</li>)}</ol></section>}
        {item.last_decision && <section className="space-y-2"><h3 className="text-sm font-medium">{item.type==='deadline_verification'?'Legal date decision recorded':(item.type==='placement_conflict'||item.type==='multi_placement_conflict') && item.last_decision.action==='keep' ? 'Current filing kept' : (item.type==='placement_conflict'||item.type==='multi_placement_conflict') && item.last_decision.action==='move' ? 'Document moved' : item.last_decision.action === 'select_candidate' ? 'Recorded outcome' : item.last_decision.action === 'continue_manual' ? 'Manual continuation recorded' : item.last_decision.action === 'select_destination' ? 'Placement recorded' : 'Clarification requested'}</h3>{item.type!=='deadline_verification'&&item.type!=='multi_placement_conflict'&&item.last_decision.selected_candidate_id && <p className="break-words text-sm">Selected: {reviewValueLabel(item.evidence.find(e => e.candidate_id === item.last_decision?.selected_candidate_id)?.value)}</p>}{item.last_decision.placement_candidate_id && <p className="break-words text-sm">Destination: {placementValue(item.evidence.find(e => e.candidate_id === item.last_decision?.placement_candidate_id)?.value)?.matter_title}</p>}{item.type==='placement_conflict' && <p className="break-words text-sm">Recorded {item.last_decision.action==='move' ? `Move from ${recordedSource} to ${recordedTarget}` : `Keep in ${recordedSource}`}.</p>}{item.type==='multi_placement_conflict' && <p className="break-words text-sm">Recorded {item.last_decision.action==='move' ? `Move from ${recordedSource} to ${multiCandidateValue(item.evidence.find(e=>e.candidate_id===item.last_decision?.selected_candidate_id)?.value)?.target_matter_title??'the chosen Matter'}` : `Keep in ${recordedSource}`}.</p>}<p className="break-words text-sm">{item.type==='placement_conflict'||item.type==='multi_placement_conflict' ? `Reason: ${item.last_decision.reason}` : item.last_decision.reason}</p></section>}
        {canResolve && item.type==='multi_placement_conflict' ? <fieldset className="space-y-3"><legend className="text-sm font-medium">Decide this current filing</legend>
          <p className="text-caption text-[var(--text-muted)]">Inspect each printed source. Keep records why none changes this filing; Move requires exactly one eligible verified Matter and that target’s current dependency impact.</p>
          <label className="flex min-h-11 cursor-pointer items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border)] p-3"><input type="radio" name="multi-placed-outcome" checked={choice==='keep'} onChange={()=>void chooseMultiPlacement(null)} className="mt-1 size-4 accent-[var(--primary)]"/><span className="text-sm">Keep current filing in {item.matter_title}</span></label>
          {item.evidence.map(candidate=>{const value=multiCandidateValue(candidate.value);return value&&<label key={candidate.candidate_id} className="flex min-h-11 cursor-pointer items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border)] p-3"><input type="radio" name="multi-placed-outcome" checked={choice===value.target_matter_id} onChange={()=>void chooseMultiPlacement(value.target_matter_id)} className="mt-1 size-4 accent-[var(--primary)]"/><span className="min-w-0 break-words text-sm">Move to {value.target_matter_title} ({value.target_matter_code})<span className="mt-1 block text-caption text-[var(--text-muted)]">{value.target_client_name} · {value.display} · source page {candidate.page_number}</span></span></label>})}
          {choice&&choice!=='keep'&&<div className="space-y-2 border-l-2 border-[var(--border-strong)] pl-3" role="status">{previewPending?<p className="text-sm">Checking this target’s Move impact…</p>:selectedMultiPreview?.code==='ok'?<><p className="text-sm">Current impact: {selectedMultiPreview.documentTitle} · {selectedMultiPreview.sourceMatterTitle} → {selectedMultiPreview.targetMatterTitle}</p><ul className="space-y-1 text-caption text-[var(--text-secondary)]">{selectedMultiPreview.categories?.filter(category=>category.count>0).map(category=><li key={category.key}>{category.label}: {category.count}</li>)}</ul>{selectedMultiPreview.blockers?.length?<p className="text-sm">Move blocked: {selectedMultiPreview.blockers.join('; ')}</p>:<p className="text-caption text-[var(--text-muted)]">No current blockers. Changed dependencies invalidate this preview.</p>}</>:<p className="text-sm">No current Move preview. Select this Matter again to refresh.</p>}</div>}
        </fieldset> : null}
        {item.type==='multi_placement_conflict' ? (!canResolve && item.status!=='closed' ? <p className="text-sm text-[var(--text-muted)]">The exact candidate set or filing is no longer current, or your access is read-only. Refresh Review before deciding.</p> : null) : canResolve && item.type==='placement_conflict' ? <fieldset className="space-y-3"><legend className="text-sm font-medium">Decide the current filing</legend>
          <p className="text-caption text-[var(--text-muted)]">Inspect the exact source before deciding. Keep records why the verified key does not change this filing. Move requires the current dependency impact and can be blocked.</p>
          <label className="flex min-h-11 cursor-pointer items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border)] p-3"><input type="radio" name="placed-outcome" checked={choice==='keep'} onChange={()=>void choosePlacement('keep')} className="mt-1 size-4 accent-[var(--primary)]"/><span className="text-sm">Keep current filing<span className="mt-1 block text-caption text-[var(--text-muted)]">Document and exact Workbench target remain in {item.matter_title}; explain why.</span></span></label>
          <label className="flex min-h-11 cursor-pointer items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border)] p-3"><input type="radio" name="placed-outcome" checked={choice==='move'} onChange={()=>void choosePlacement('move')} className="mt-1 size-4 accent-[var(--primary)]"/><span className="text-sm">Move to {item.target_matter_title}<span className="mt-1 block text-caption text-[var(--text-muted)]">Same logical document, version and PDF asset; dependent context may change.</span></span></label>
          {choice==='move' && <div className="space-y-2 border-l-2 border-[var(--border-strong)] pl-3" role="status">
            {previewPending ? <p className="text-sm">Checking current Move impact…</p> : movePreview?.code==='ok' ? <><p className="text-sm">Current impact: {movePreview.documentTitle} · {movePreview.sourceMatterTitle} → {movePreview.targetMatterTitle}</p><ul className="space-y-1 text-caption text-[var(--text-secondary)]">{movePreview.categories?.filter(category=>category.count>0).map(category=><li key={category.key}>{category.label}: {category.count}</li>)}</ul>{movePreview.blockers?.length ? <><p className="text-sm">Move is blocked:</p><ul className="space-y-1 text-sm">{movePreview.blockers.map((blocker,index)=><li key={index}>{blocker}</li>)}</ul></> : <p className="text-caption text-[var(--text-muted)]">No current blockers. A changed dependency invalidates this preview.</p>}</> : <p className="text-sm">No current Move preview. Choose Move again to refresh.</p>}
          </div>}
        </fieldset> : canResolve && item.type==='deadline_verification' ? <fieldset className="space-y-3"><legend className="text-sm font-medium">Decide this cited legal date</legend>
          <p className="text-caption text-[var(--text-muted)]">Verify only after checking the exact PDF. Correct supplies a human date; reject or clear leaves no verified date.</p>
          {(['verify','correct','reject','clear'] as const).map(action=><label key={action} className="flex min-h-11 cursor-pointer items-center gap-3 rounded-[var(--radius-sm)] border border-[var(--border)] p-3"><input type="radio" name="deadline-outcome" checked={choice===action} onChange={()=>setChoice(action)} className="size-4 accent-[var(--primary)]"/><span className="text-sm">{({verify:'Verify source date',correct:'Correct date',reject:'Reject candidate',clear:'Clear proposed date'} as const)[action]}</span></label>)}
          {choice==='correct'&&<div><Label htmlFor="review-corrected-date">Human-corrected legal date</Label><Input id="review-corrected-date" type="date" value={correctedDate} onChange={event=>setCorrectedDate(event.target.value)} aria-describedby="review-corrected-help"/><p id="review-corrected-help" className="text-caption text-[var(--text-muted)]">Enter the date supported by your cited source or a human-checked basis; explain it in the confirmation reason.</p></div>}
        </fieldset> : canResolve && item.type === 'ambiguous_placement' ? <fieldset className="space-y-3"><legend className="text-sm font-medium">Choose one eligible Matter</legend>
          <p className="text-caption text-[var(--text-muted)]">The PDF stays in global Intake until this typed decision commits.</p>
          {item.evidence.map(candidate => { const value = placementValue(candidate.value); return value && <label key={candidate.candidate_id} className="flex min-h-11 cursor-pointer items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border)] p-3"><input type="radio" name="placement-destination" className="mt-1 size-4 shrink-0 accent-[var(--primary)]" checked={choice === candidate.candidate_id} onChange={() => setChoice(candidate.candidate_id)} /><span className="min-w-0 break-words text-sm">Place in {value.matter_title}<span className="mt-1 block text-caption text-[var(--text-muted)]">{value.client_name}{value.matter_code ? ` · ${value.matter_code}` : ''}</span></span></label> })}
        </fieldset> : canResolve && item.type === 'processing_recovery' ? <fieldset className="space-y-3"><legend className="text-sm font-medium">Enter verified document details</legend>
          <p className="text-caption text-[var(--text-muted)]">Use the exact PDF above. These values become auditable manual metadata for the current version.</p>
          <div><Label htmlFor="manual-doc-type">Document type</Label><select id="manual-doc-type" className="input-base min-h-11" value={manual.doc_type} onChange={event => setManual(value => ({ ...value, doc_type: event.target.value }))}>{['DRC-01','DRC-01A','DRC-01C','DRC-03','DRC-07','SCN','OIO','OIA','APL-01','APL-02','APL-05','STAY','REPLY','HC_PETITION','HC_ORDER','SC_PETITION','SC_ORDER','OTHER'].map(value => <option key={value}>{value}</option>)}</select></div>
          <div><Label htmlFor="manual-reference">Reference number</Label><Input id="manual-reference" value={manual.reference_number} maxLength={300} onChange={event => setManual(value => ({ ...value, reference_number: event.target.value }))} /></div>
          <div><Label htmlFor="manual-date">Document date</Label><Input id="manual-date" type="date" value={manual.document_date} onChange={event => setManual(value => ({ ...value, document_date: event.target.value }))} /></div>
          <div><Label htmlFor="manual-direction">Direction</Label><select id="manual-direction" className="input-base min-h-11" value={manual.direction} onChange={event => setManual(value => ({ ...value, direction: event.target.value }))}><option value="incoming">Incoming</option><option value="outgoing">Outgoing</option></select></div>
          <div><Label htmlFor="manual-issued-by">Issued by</Label><Input id="manual-issued-by" value={manual.issued_by} maxLength={300} onChange={event => setManual(value => ({ ...value, issued_by: event.target.value }))} /></div>
        </fieldset> : canResolve ? <fieldset className="space-y-3"><legend className="mb-3 text-sm font-medium">Choose an outcome</legend>
          {item.allowed_actions.includes('select_candidate') && item.evidence.filter(evidence => evidence.selectable).map(evidence => <label key={evidence.candidate_id} className="flex min-h-11 cursor-pointer items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border)] p-3"><input type="radio" name="review-outcome" className="mt-1 size-4 shrink-0 accent-[var(--primary)]" checked={choice === evidence.candidate_id} onChange={() => setChoice(evidence.candidate_id)} /><span className="min-w-0 break-words text-sm">Use {reviewValueLabel(evidence.value)}<span className="mt-1 block text-caption text-[var(--text-muted)]">Accept evidence {evidence.ordinal}; reject competing item candidates and close Review.</span></span></label>)}
          <label className="flex min-h-11 cursor-pointer items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border)] p-3"><input type="radio" name="review-outcome" className="mt-1 size-4 shrink-0 accent-[var(--primary)]" checked={choice === 'clarify'} onChange={() => setChoice('clarify')} /><span className="text-sm">Request clarification<span className="mt-1 block text-caption text-[var(--text-muted)]">Record what needs clarification. Keep this item in Needs review.</span></span></label>
          {!item.allowed_actions.includes('select_candidate') && <p className="text-sm text-[var(--text-muted)]">No supported candidate can resolve this conflict. Describe the clarification needed.</p>}
        </fieldset> : item.status !== 'closed' && <p className="text-sm text-[var(--text-muted)]">{item.type==='placement_conflict' && item.conflict_current===false ? 'The exact source, verified key, or target Matter is no longer current and this decision is unavailable. Refresh Review after the source or destination is restored or reevaluated.' : 'Read-only access. An authorised team member can record a decision.'}</p>}
      </>}
    </div>
    <footer className="shrink-0 border-t border-[var(--border)] p-3">
      {tab === 'evidence' ? <Button variant="outline" className="w-full" onClick={onDecisionTab}>View decision</Button> : canResolve && item.type==='multi_placement_conflict' ? <Button className="w-full" disabled={!choice || previewPending || pending || (choice!=='keep' && !hasCurrentMultiMoveImpact(multiMovePreview,item.id,choice,previewPending))} onClick={()=>{
        if(choice!=='keep'&&!hasCurrentMultiMoveImpact(multiMovePreview,item.id,choice,previewPending)) return
        setConfirmation({itemId:item.id,revision:item.revision,action:choice==='keep'?'keep':'move',targetMatterId:choice==='keep'?null:choice,impactFingerprint:choice==='keep'?null:selectedMultiPreview?.fingerprint??null,reason:'',idempotencyKey:crypto.randomUUID()})
      }}>Review filing decision</Button> : canResolve && item.type==='placement_conflict' ? <Button className="w-full" disabled={!choice || previewPending || pending || (choice==='move' && (movePreview?.code!=='ok' || !movePreview.fingerprint || !!movePreview.blockers?.length))} onClick={()=>setConfirmation({itemId:item.id,revision:item.revision,action:choice as PlacementConflictResolution['action'],impactFingerprint:choice==='move'?movePreview?.fingerprint??null:null,reason:'',idempotencyKey:crypto.randomUUID()})}>Review filing decision</Button> : canResolve && item.type==='deadline_verification' ? <Button className="w-full" disabled={!choice || (choice==='correct'&&!correctedDate) || pending} onClick={()=>setConfirmation({itemId:item.id,revision:item.revision,action:choice as DeadlineReviewResolution['action'],correctedDueDate:choice==='correct'?correctedDate:null,reason:'',idempotencyKey:crypto.randomUUID()})}>Review date decision</Button> : canResolve && item.type === 'ambiguous_placement' ? <Button className="w-full" disabled={!choice || pending} onClick={() => setConfirmation({ itemId: item.id, revision: item.revision, action: 'select_destination', placementCandidateId: choice, reason: '', idempotencyKey: crypto.randomUUID() })}>Review destination</Button> : canResolve && item.type === 'processing_recovery' ? <Button className="w-full" disabled={!manual.reference_number.trim() || !manual.document_date || !manual.issued_by.trim() || pending} onClick={() => setConfirmation({ itemId: item.id, revision: item.revision, action: 'continue_manual', metadata: manual as ProcessingRecoveryResolution['metadata'], reason: '', idempotencyKey: crypto.randomUUID() })}>Review manual continuation</Button> : canResolve && item.type!=='multi_placement_conflict' ? <Button className="w-full" disabled={!choice || pending} onClick={() => setConfirmation({ itemId: item.id, revision: item.revision, action: choice === 'clarify' ? 'request_clarification' : 'select_candidate', candidateId: selected?.candidate_id ?? null, reason: '', idempotencyKey: crypto.randomUUID() })}>Review decision</Button> : <p className="text-caption text-[var(--text-muted)]">{item.status === 'closed' ? 'This Review item is closed.' : 'No decision actions available.'}</p>}
    </footer>
    <Dialog open={confirmation !== null} onOpenChange={open => { if (!open && !pending) { setConfirmation(null); setReason('') } }}><DialogContent><DialogHeader><DialogTitle>{confirmation?.action==='keep'?'Keep this document in its current Matter?':confirmation?.action==='move'?'Move this document to the chosen Matter?':confirmation && ['verify','correct','reject','clear'].includes(confirmation.action) ? 'Record this legal date decision?' : confirmation?.action === 'select_candidate' ? 'Use this extracted value?' : confirmation?.action === 'continue_manual' ? 'Continue with manual metadata?' : confirmation?.action === 'select_destination' ? 'Place this Intake PDF?' : 'Request clarification?'}</DialogTitle><DialogDescription>{confirmation?.action==='keep'?`Keep ${item.document_title} in ${item.matter_title}. The verified candidate set and your reason remain in Review history; unchanged source evidence will not raise this conflict again.`:confirmation?.action==='move'?`Move ${item.document_title} from ${item.matter_title} to ${item.type==='multi_placement_conflict'?multiCandidateValue(selected?.value)?.target_matter_title:item.target_matter_title}. This target’s current impact will be rechecked transactionally; the same document, version and PDF source remain available.`:confirmation && ['verify','correct','reject','clear'].includes(confirmation.action) ? `${confirmation.action==='correct'?'Correct to '+correctedDate:confirmation.action==='verify'?'Verify the cited date '+item.candidate_due_date:confirmation.action==='reject'?'Reject this candidate':'Clear this proposed date'}. The source stays immutable; your reason and decision enter history.` : confirmation?.action === 'select_candidate' ? `Use ${reviewValueLabel(selected?.value)}. Competing item candidates will be rejected and this Review item will close.` : confirmation?.action === 'continue_manual' ? 'Record the verified document details, close this recovery item, and continue in the existing Workbench. Automated extraction will not be retried.' : confirmation?.action === 'select_destination' ? `Create the canonical document in ${placementValue(selected?.value)?.matter_title ?? 'the selected Matter'}, close Review, and open the exact new version at page 1.` : 'Record what needs clarification. The current value stays unchanged and this item remains in Needs review.'}</DialogDescription></DialogHeader>
      <div className="min-w-0 space-y-2"><Label htmlFor="review-reason">Reason</Label><textarea id="review-reason" className="input-base min-h-24 max-h-40 resize-y" rows={4} value={reason} maxLength={500} disabled={pending} onChange={event => { const next = event.target.value.replace(/[\r\n]/g, ' '); setReason(next); setConfirmation(value => value && { ...value, reason: next }) }} aria-describedby="review-reason-help" /><p id="review-reason-help" className="text-caption text-[var(--text-muted)]">Explain the decision in up to 500 characters. {reason.length}/500</p>{message && <p role="status" className="text-sm">{message}</p>}</div>
      <DialogFooter><Button variant="ghost" disabled={pending} onClick={() => { setConfirmation(null); setReason('') }}>Return to decision</Button><Button loading={pending} disabled={reason.trim().length<2} onClick={confirm}>{confirmation?.action==='keep'?'Keep current filing':confirmation?.action==='move'?'Move document':confirmation && ['verify','correct','reject','clear'].includes(confirmation.action) ? 'Record date decision' : confirmation?.action === 'select_candidate' ? 'Confirm selected value' : confirmation?.action === 'continue_manual' ? 'Continue manually' : confirmation?.action === 'select_destination' ? 'Place in selected Matter' : 'Request clarification'}</Button></DialogFooter>
    </DialogContent></Dialog>
  </>
}
