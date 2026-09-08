'use client'

import { useId, useState } from 'react'
import { useRouter } from 'next/navigation'

import { Button } from '@/components/ui/button'
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { isMatterTimelineFilter } from '@/lib/matters/workspace-timeline-page'
import { buildMatterTimelineFiltersHref } from '@/lib/matters/workspace-route'

type Direction = '' | 'incoming' | 'outgoing'
type DatePresence = '' | 'dated' | 'undated'
type Attention = '' | 'processing' | 'review' | 'failed' | 'pdf-not-attached'

function valueFor(filters: readonly string[], prefix: string) {
  return filters.find((filter) => filter.startsWith(prefix))?.slice(prefix.length) ?? ''
}

export function MatterTimelineFilters(props: { matterId: string; entries: Array<[string, string]>; filters: string[] }) {
  return <MatterTimelineFiltersDialog key={props.filters.join('\u0000')} {...props} />
}

function MatterTimelineFiltersDialog({ matterId, entries, filters }: { matterId: string; entries: Array<[string, string]>; filters: string[] }) {
  const router = useRouter()
  const id = useId()
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState(() => valueFor(filters, 'q:'))
  const [documentType, setDocumentType] = useState(() => valueFor(filters, 'type:'))
  const [direction, setDirection] = useState<Direction>(() => filters.includes('incoming') ? 'incoming' : filters.includes('outgoing') ? 'outgoing' : '')
  const [datePresence, setDatePresence] = useState<DatePresence>(() => filters.includes('dated') ? 'dated' : filters.includes('undated') ? 'undated' : '')
  const [attention, setAttention] = useState<Attention>(() => valueFor(filters, 'attention:') as Attention)
  const [fromDate, setFromDate] = useState(() => valueFor(filters, 'from:'))
  const [toDate, setToDate] = useState(() => valueFor(filters, 'to:'))

  const resetDraft = (nextFilters: readonly string[]) => {
    setQuery(valueFor(nextFilters, 'q:'))
    setDocumentType(valueFor(nextFilters, 'type:'))
    setDirection(nextFilters.includes('incoming') ? 'incoming' : nextFilters.includes('outgoing') ? 'outgoing' : '')
    setDatePresence(nextFilters.includes('dated') ? 'dated' : nextFilters.includes('undated') ? 'undated' : '')
    setAttention(valueFor(nextFilters, 'attention:') as Attention)
    setFromDate(valueFor(nextFilters, 'from:'))
    setToDate(valueFor(nextFilters, 'to:'))
  }

  const navigate = (nextFilters: readonly string[]) => {
    router.push(buildMatterTimelineFiltersHref(matterId, entries, nextFilters), { scroll: false })
    setOpen(false)
  }
  const invalidRange = Boolean(
    (fromDate && !isMatterTimelineFilter(`from:${fromDate}`))
    || (toDate && !isMatterTimelineFilter(`to:${toDate}`))
    || (fromDate && toDate && fromDate > toDate),
  )
  const apply = () => {
    if (invalidRange) return
    const trimmedQuery = query.trim()
    const trimmedDocumentType = documentType.trim()
    const next = [trimmedQuery ? `q:${trimmedQuery}` : '', trimmedDocumentType ? `type:${trimmedDocumentType}` : '', direction, datePresence, fromDate ? `from:${fromDate}` : '', toDate ? `to:${toDate}` : '', attention ? `attention:${attention}` : ''].filter(Boolean)
    if (next.every(isMatterTimelineFilter)) navigate(next)
  }
  const selectClassName = 'h-11 w-full rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3.5 text-sm text-[var(--text-primary)] outline-none focus:border-[var(--primary)] focus:ring-2 focus:ring-[var(--accent-ring)]'

  return (
    <Dialog open={open} onOpenChange={(nextOpen) => { if (nextOpen) resetDraft(filters); setOpen(nextOpen) }}>
      <DialogTrigger asChild><Button id={`matter-timeline-filter-${matterId}`} type="button" variant="secondary" className="min-h-11">Filter{filters.length ? ` (${filters.length})` : ''}</Button></DialogTrigger>
      <DialogContent showClose={false} className="top-4 max-h-[calc(100dvh-2rem)] translate-y-0 overflow-y-auto sm:left-auto sm:right-6 sm:top-16 sm:w-[392px] sm:max-w-[calc(100vw-3rem)] sm:translate-x-0">
        <DialogHeader><DialogTitle>Timeline filters</DialogTitle><DialogDescription>Limit the chronology using effective proceeding metadata.</DialogDescription></DialogHeader>
        <div className="grid gap-4">
          <div><Label htmlFor={`${id}-query`}>Title or reference</Label><Input id={`${id}-query`} value={query} maxLength={78} onChange={(event) => setQuery(event.target.value)} /></div>
          <div><Label htmlFor={`${id}-type`}>Document type</Label><Input id={`${id}-type`} value={documentType} maxLength={75} onChange={(event) => setDocumentType(event.target.value)} /></div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div><Label htmlFor={`${id}-direction`}>Direction</Label><select id={`${id}-direction`} className={selectClassName} value={direction} onChange={(event) => setDirection(event.target.value as Direction)}><option value="">Any direction</option><option value="incoming">Incoming</option><option value="outgoing">Outgoing</option></select></div>
            <div><Label htmlFor={`${id}-presence`}>Date presence</Label><select id={`${id}-presence`} className={selectClassName} value={datePresence} onChange={(event) => setDatePresence(event.target.value as DatePresence)}><option value="">Dated or undated</option><option value="dated">Dated only</option><option value="undated">Undated only</option></select></div>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div><Label htmlFor={`${id}-from`}>From</Label><Input id={`${id}-from`} type="date" value={fromDate} error={invalidRange ? 'Invalid date range' : undefined} aria-invalid={invalidRange || undefined} aria-describedby={invalidRange ? `${id}-range-error` : undefined} onChange={(event) => setFromDate(event.target.value)} /></div>
            <div><Label htmlFor={`${id}-to`}>To</Label><Input id={`${id}-to`} type="date" value={toDate} error={invalidRange ? 'Invalid date range' : undefined} aria-invalid={invalidRange || undefined} aria-describedby={invalidRange ? `${id}-range-error` : undefined} onChange={(event) => setToDate(event.target.value)} /></div>
          </div>
          {invalidRange && <p id={`${id}-range-error`} role="alert" className="text-sm text-[var(--danger)]">Enter valid dates with From on or before To.</p>}
          <div><Label htmlFor={`${id}-attention`}>Attention</Label><select id={`${id}-attention`} className={selectClassName} value={attention} onChange={(event) => setAttention(event.target.value as Attention)}><option value="">Any attention state</option><option value="processing">Processing</option><option value="review">Review</option><option value="failed">Failed</option><option value="pdf-not-attached">PDF not attached</option></select></div>
        </div>
        <DialogFooter className="sm:justify-between">
          <Button type="button" variant="ghost" onClick={() => navigate([])}>Clear filters</Button>
          <div className="flex flex-col-reverse gap-2 sm:flex-row"><DialogClose asChild><Button type="button" variant="secondary">Close</Button></DialogClose><Button type="button" disabled={invalidRange} onClick={apply}>Apply filters</Button></div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
