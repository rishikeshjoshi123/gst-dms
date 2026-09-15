'use client'

import { useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { CalendarClock, CheckCircle2, FileClock, Pencil, Plus, XCircle } from 'lucide-react'
import { amendManualLegalDeadline, createManualLegalDeadline, recordManualLegalDeadlineOutcome } from '@/lib/actions/deadlines'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { FormField, Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { DEADLINE_TYPE_LABELS, TEMPORAL_LABELS, type LegalDeadlineType, type ManualDeadlineAgenda, type ManualDeadlineItem } from '@/lib/deadlines/manual'
import { cn } from '@/lib/utils'
import { canonicalDocumentPath } from '@/lib/canonical-document-route'

type EditorMode = 'create' | 'amend'
type Outcome = 'satisfied' | 'cancelled'
const TYPES = Object.entries(DEADLINE_TYPE_LABELS) as Array<[LegalDeadlineType, string]>
const temporalVariant = { missed: 'danger', due_today: 'warning', due_soon: 'warning', upcoming: 'muted' } as const

function dateLabel(value: string) {
  return new Intl.DateTimeFormat('en-IN', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' }).format(new Date(`${value}T00:00:00Z`))
}
function DeadlineEditor({ matterId, item, mode, open, onOpenChange, returnFocus }: { matterId: string; item?: ManualDeadlineItem; mode: EditorMode; open: boolean; onOpenChange(open: boolean): void; returnFocus: React.RefObject<HTMLButtonElement | null> }) {
  const idempotency = useRef(crypto.randomUUID())
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError('')
    const form = new FormData(event.currentTarget)
    const common = { matterId, title:String(form.get('title') ?? ''), obligation:String(form.get('obligation') ?? ''), legalType:String(form.get('legalType') ?? ''), dueDate:String(form.get('dueDate') ?? ''), manualBasis:String(form.get('manualBasis') ?? ''), idempotencyKey:idempotency.current }
    const response = mode === 'create'
      ? await createManualLegalDeadline(common)
      : await amendManualLegalDeadline({ ...common, deadlineId:item?.id, expectedRevision:item?.revision, reason:String(form.get('reason') ?? '') })
    setBusy(false)
    if (response.code === 'ok') { idempotency.current=crypto.randomUUID(); onOpenChange(false) }
    else setError(response.message)
  }
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent onCloseAutoFocus={(event)=>{event.preventDefault();returnFocus.current?.focus()}} className="max-h-[calc(100dvh-2rem)] overflow-y-auto sm:max-w-xl">
    <DialogHeader><DialogTitle>{mode === 'create' ? 'Add legal deadline' : item?.origin==='document_explicit'?'Correct legal deadline':'Amend legal deadline'}</DialogTitle><DialogDescription>{mode === 'create' ? 'A manual date begins verified. State the source or legal basis explicitly.' : 'The current version remains in history. Explain why this amendment is needed.'}</DialogDescription></DialogHeader>
    <form onSubmit={submit} className="space-y-4">
      <FormField label="Concise title" htmlFor={`${mode}-deadline-title`} required><Input id={`${mode}-deadline-title`} name="title" maxLength={160} required defaultValue={item?.title} /></FormField>
      <FormField label="Obligation" htmlFor={`${mode}-deadline-obligation`} required><Input id={`${mode}-deadline-obligation`} name="obligation" maxLength={1000} required defaultValue={item?.obligation} /></FormField>
      <div><Label htmlFor={`${mode}-deadline-type`} required>Legal deadline type</Label><select id={`${mode}-deadline-type`} name="legalType" required defaultValue={item?.legal_type ?? 'reply_due'} className="h-11 w-full rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] md:h-10">{TYPES.map(([value,label]) => <option key={value} value={value}>{label}</option>)}</select></div>
      <FormField label="Due date" htmlFor={`${mode}-deadline-date`} hint="Date only. The organisation operational timezone determines Due today and Missed." required><Input id={`${mode}-deadline-date`} name="dueDate" type="date" required defaultValue={item?.due_date} /></FormField>
      <FormField label="Manual basis" htmlFor={`${mode}-deadline-basis`} hint="Identify the order, instruction, provision, filing rule, or other human-checked basis." required><Input id={`${mode}-deadline-basis`} name="manualBasis" maxLength={500} required defaultValue={mode === 'amend' ? item?.manual_basis??'' : ''} /></FormField>
      {mode === 'amend' && <FormField label="Reason for amendment" htmlFor="deadline-amend-reason" required><Input id="deadline-amend-reason" name="reason" maxLength={500} required /></FormField>}
      {error && <p role="alert" className="text-sm text-[var(--danger)]">{error}</p>}
      <DialogFooter><Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Keep unchanged</Button><Button type="submit" loading={busy}>{mode === 'create' ? 'Add deadline' : item?.origin==='document_explicit'?'Correct deadline':'Amend deadline'}</Button></DialogFooter>
    </form>
  </DialogContent></Dialog>
}

function OutcomeDialog({ matterId, item, outcome, open, onOpenChange }: { matterId:string; item:ManualDeadlineItem; outcome:Outcome; open:boolean; onOpenChange(open:boolean):void }) {
  const idempotency=useRef(crypto.randomUUID()); const [busy,setBusy]=useState(false); const [error,setError]=useState('')
  async function submit(event:React.FormEvent<HTMLFormElement>) { event.preventDefault(); setBusy(true); setError(''); const form=new FormData(event.currentTarget); const response=await recordManualLegalDeadlineOutcome({matterId,deadlineId:item.id,expectedRevision:item.revision,outcome,reason:String(form.get('reason')??''),idempotencyKey:idempotency.current}); setBusy(false); if(response.code==='ok'){idempotency.current=crypto.randomUUID();onOpenChange(false)}else setError(response.message) }
  const cancelling=outcome==='cancelled'
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent><DialogHeader><DialogTitle>{cancelling?'Cancel legal deadline?':'Mark legal deadline satisfied?'}</DialogTitle><DialogDescription>{item.title} · due {dateLabel(item.due_date)}. This records a permanent outcome while preserving every prior version.</DialogDescription></DialogHeader><form onSubmit={submit}><FormField label={cancelling?'Reason for cancellation':'Outcome note (optional)'} htmlFor={`deadline-${outcome}-reason`} required={cancelling}><Input id={`deadline-${outcome}-reason`} name="reason" maxLength={500} required={cancelling}/></FormField>{error&&<p role="alert" className="mt-3 text-sm text-[var(--danger)]">{error}</p>}<DialogFooter><Button type="button" variant="outline" onClick={()=>onOpenChange(false)}>Keep open</Button><Button type="submit" variant={cancelling?'destructive':'default'} loading={busy}>{cancelling?'Cancel deadline':'Mark satisfied'}</Button></DialogFooter></form></DialogContent></Dialog>
}

function DeadlineBadges({ item }: { item:ManualDeadlineItem }) { return <div className="flex flex-wrap gap-1.5"><Badge variant={item.verification_state==='provisional'?'warning':temporalVariant[item.temporal]} fixedWidth="lg">{item.verification_state==='provisional'?'Needs verification':TEMPORAL_LABELS[item.temporal]}</Badge><Badge variant={item.lifecycle==='open'?'default':item.lifecycle==='satisfied'?'success':'muted'} fixedWidth="lg">{item.lifecycle==='open'?'Open':item.lifecycle==='satisfied'?'Satisfied':'Cancelled'}</Badge></div> }

export function MatterDeadlineAgenda({ matterId, agenda, readOnly=false }: { matterId:string; agenda:ManualDeadlineAgenda; readOnly?:boolean }) {
  const [selectedId,setSelectedId]=useState<string|null>(null); const [mobileDetail,setMobileDetail]=useState(false); const [editor,setEditor]=useState<EditorMode|null>(null); const [outcome,setOutcome]=useState<Outcome|null>(null)
  const editorReturnFocus=useRef<HTMLButtonElement>(null)
  const selected=useMemo(()=>agenda.items.find((item)=>item.id===selectedId)??null,[agenda.items,selectedId]); const canMutate=agenda.canMutate&&!readOnly
  return <div className="flex h-full min-h-0 flex-col overflow-hidden pt-2 md:pt-3">
    <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 py-2 md:px-4"><div className="min-w-0 flex-1"><p className="text-sm font-medium">Legal date agenda</p><p className="truncate text-xs text-[var(--text-muted)]">Date-only status uses {agenda.timezone} · as of {dateLabel(agenda.asOfDate)}. Proposed dates require Review; no reminders are active.</p></div>{canMutate&&<Button size="sm" onClick={(event)=>{editorReturnFocus.current=event.currentTarget;setEditor('create')}}><Plus className="size-4"/>Add deadline</Button>}{!canMutate&&<Badge variant="muted">Read only</Badge>}</div>
    {agenda.items.length===0?<div className="flex min-h-0 flex-1 items-center justify-center overflow-y-auto p-6"><div className="max-w-sm text-center"><CalendarClock className="mx-auto size-7 text-[var(--text-muted)]"/><h2 className="mt-3 text-section-heading">No legal dates yet</h2><p className="mt-1 text-sm text-[var(--text-muted)]">Add a human-checked legal obligation and date, or review a source-stated date after PDF processing.</p></div></div>:
      <div className="grid min-h-0 flex-1 overflow-y-auto overscroll-contain xl:grid-cols-[minmax(0,3fr)_minmax(20rem,2fr)] xl:overflow-hidden">
        <div className={cn('min-h-0 overflow-visible xl:overflow-y-auto xl:overscroll-contain',mobileDetail&&'hidden md:block')}>
          <div className="hidden md:block"><Table><TableCaption>Legal dates with explicit origin and verification</TableCaption><TableHeader sticky><TableRow><TableHead>Date</TableHead><TableHead>Obligation</TableHead><TableHead>Kind</TableHead><TableHead>Origin</TableHead><TableHead>Lifecycle and timing</TableHead><TableHead><span className="sr-only">Select</span></TableHead></TableRow></TableHeader><TableBody>{agenda.items.map(item=><TableRow key={item.id} selected={selected?.id===item.id} interactive className={cn('min-h-14',item.lifecycle!=='open'&&'text-[var(--text-muted)]')}><TableCell className="whitespace-nowrap font-mono">{dateLabel(item.due_date)}</TableCell><TableCell><span className="block font-medium">{item.title}</span><span className="line-clamp-1 text-xs text-[var(--text-muted)]">{item.obligation}</span></TableCell><TableCell>Legal deadline</TableCell><TableCell>{item.origin==='manual'?'Manual':'Extracted'} · {item.verification_state==='verified'?'Verified':'Provisional'}</TableCell><TableCell><DeadlineBadges item={item}/></TableCell><TableCell><Button variant="ghost" size="sm" onClick={()=>setSelectedId(item.id)}>View details</Button></TableCell></TableRow>)}</TableBody></Table></div>
          <ul className="divide-y divide-[var(--border-subtle)] md:hidden">{agenda.items.map(item=><li key={item.id}><button type="button" onClick={()=>{setSelectedId(item.id);setMobileDetail(true)}} className="min-h-11 w-full px-3 py-3 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]"><div className="flex items-start gap-3"><span className="shrink-0 font-mono text-xs">{dateLabel(item.due_date)}</span><span className="min-w-0 flex-1"><span className="block break-words text-sm font-medium">{item.title}</span><span className="mt-1 block text-xs text-[var(--text-muted)]">Legal deadline · {item.origin==='manual'?'Manual':'Extracted'} · {item.verification_state==='verified'?'Verified':'Provisional'}</span><span className="mt-2 block"><DeadlineBadges item={item}/></span></span></div></button></li>)}</ul>
        </div>
        {selected&&<aside aria-label="Selected deadline details" className={cn('min-h-0 overflow-visible border-t border-[var(--border)] bg-[var(--surface)] p-4 xl:overflow-y-auto xl:overscroll-contain xl:border-l xl:border-t-0',!mobileDetail&&'hidden md:block')}>
          <Button variant="ghost" size="sm" className="mb-3 md:hidden" onClick={()=>setMobileDetail(false)}>Back to deadlines</Button>
          <div className="flex items-start gap-3"><FileClock className="mt-0.5 size-5 shrink-0 text-[var(--primary)]"/><div className="min-w-0"><h2 className="break-words text-section-heading">{selected.title}</h2><p className="mt-1 break-words text-sm text-[var(--text-secondary)]">{selected.obligation}</p></div></div>
          <div className="mt-4 flex flex-wrap gap-1.5"><Badge variant="outline">Legal deadline</Badge><Badge variant="outline">{selected.origin==='manual'?'Manual':'Extracted'} origin</Badge><Badge variant={selected.verification_state==='verified'?'success':'warning'}>{selected.verification_state==='verified'?'Verified':'Provisional'}</Badge></div><div className="mt-3"><DeadlineBadges item={selected}/></div>
          <dl className="mt-5 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-3 gap-y-2 text-sm"><dt className="text-[var(--text-muted)]">Due date</dt><dd className="font-mono">{dateLabel(selected.due_date)}</dd><dt className="text-[var(--text-muted)]">Type</dt><dd>{DEADLINE_TYPE_LABELS[selected.legal_type]}</dd><dt className="text-[var(--text-muted)]">Timezone rule</dt><dd className="break-words">End of day in {agenda.timezone}</dd></dl>
          {selected.source&&<section className="mt-5 space-y-2"><h3 className="text-sm font-medium">Exact source evidence · Page {selected.source.page_number}</h3><blockquote className="break-words border-l-2 border-[var(--border-strong)] pl-3 text-sm">“{selected.source.quotation}”</blockquote><Link className="inline-flex min-h-11 items-center text-sm text-[var(--primary)] underline" href={canonicalDocumentPath(selected.source.document_id,{version:selected.source.document_version_id,page:String(selected.source.page_number)})}>Open exact source · Page {selected.source.page_number}</Link>{selected.verification_state==='provisional'&&<p><Link className="inline-flex min-h-11 items-center text-sm text-[var(--primary)] underline" href={`/review?item=${selected.source.review_item_id}`}>Review extracted date</Link></p>}</section>}
          {canMutate&&selected.verification_state==='verified'&&selected.lifecycle==='open'&&<div className="mt-5 flex flex-wrap gap-2"><Button variant="outline" size="sm" onClick={(event)=>{editorReturnFocus.current=event.currentTarget;setEditor('amend')}}><Pencil className="size-4"/>{selected.origin==='manual'?'Amend deadline':'Correct deadline'}</Button><Button variant="secondary" size="sm" onClick={()=>setOutcome('satisfied')}><CheckCircle2 className="size-4"/>Mark satisfied</Button><Button variant="destructive" size="sm" onClick={()=>setOutcome('cancelled')}><XCircle className="size-4"/>Cancel deadline</Button></div>}
          <section className="mt-6"><h3 className="text-sm font-semibold">History</h3><ol className="mt-3 space-y-3 border-l border-[var(--border-strong)] pl-4">{selected.history.map(entry=><li key={`${entry.kind}-${entry.revision}`} className="text-sm"><p className="font-medium">{({created:'Deadline created',extracted:'Source date proposed',amended:'Deadline amended',verify:'Source date verified',correct:'Source date corrected',reject:'Candidate rejected',clear:'Candidate cleared',satisfied:'Marked satisfied',cancelled:'Deadline cancelled'} as Record<string,string>)[entry.kind]}</p><p className="mt-0.5 text-xs text-[var(--text-muted)]">Revision {entry.revision} · {entry.actor_label} · {new Intl.DateTimeFormat('en-IN',{dateStyle:'medium',timeStyle:'short'}).format(new Date(entry.at))}</p>{entry.due_date&&<p className="mt-1 break-words text-xs">{dateLabel(entry.due_date)}{entry.manual_basis?` · ${entry.manual_basis}`:''}</p>}{entry.reason&&<p className="mt-1 break-words text-xs text-[var(--text-secondary)]">Reason: {entry.reason}</p>}</li>)}</ol></section>
        </aside>}
      </div>}
    <DeadlineEditor
      matterId={matterId}
      mode={editor ?? 'create'}
      item={editor === 'amend' ? selected ?? undefined : undefined}
      open={editor !== null}
      onOpenChange={(open) => !open && setEditor(null)}
      returnFocus={editorReturnFocus}
    />
    {selected && outcome && (
      <OutcomeDialog
        matterId={matterId}
        item={selected}
        outcome={outcome}
        open
        onOpenChange={(open) => !open && setOutcome(null)}
      />
    )}
  </div>
}
