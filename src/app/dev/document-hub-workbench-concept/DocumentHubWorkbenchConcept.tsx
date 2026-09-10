'use client'

import { useMemo, useRef, useState } from 'react'
import {
  AlertTriangle, ArrowLeft, CalendarClock, Check, CheckCircle2, ChevronDown,
  ChevronLeft, ChevronRight, CircleAlert, CircleDollarSign, FileSearch,
  FileText, Filter, Fingerprint, Gavel, Highlighter, Inbox, Loader2, MapPin,
  RefreshCw, RotateCw, Search, Upload, UserRoundCheck, X, ZoomIn, ZoomOut,
} from 'lucide-react'

import { ThemeToggle } from '@/components/nav/ThemeToggle'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuLabel, DropdownMenuRadioGroup,
  DropdownMenuRadioItem, DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import {
  Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'
import { cn } from '@/lib/utils'

type PreviewState = 'default' | 'upload' | 'loading' | 'empty' | 'error' | 'long'
type QueueFilter = 'action' | 'processing' | 'completed' | 'all'
type UploadScope = 'mine' | 'all'
type QueueStatus = 'Processing' | 'Ready' | 'Review' | 'Duplicate' | 'Failed'
type RolePreview = 'Associate' | 'Viewer'
type DetailTab = 'overview' | 'extracted'
type FindingKind = 'deadline' | 'financial' | 'identity' | 'placement' | 'processing'

type Finding = { kind: FindingKind; label: string; value: string; detail: string; page?: number; warning?: boolean }
type ExtractedField = { label: string; value: string; page?: number; mono?: boolean }
type MetadataSection = { title: string; fields: ExtractedField[] }
type SourceContext = { page: number; label: string | null }

type QueueItem = {
  id: string
  name: string
  classification: string
  uploader: string
  origin: string
  received: string
  destination: string
  stage: string
  status: QueueStatus
  pages: number
  requiresAction: boolean
  summaryLabel: string
  summaryTitle: string
  summaryBody: string
  findings: Finding[]
  metadata: MetadataSection[]
  primaryAction: string
  primaryMutation: boolean
  claimedBy?: string
  claimUntil?: string
}

const queueItems: QueueItem[] = [
  {
    id: 'placement', name: 'DRC-01A notice — August 2026.pdf', classification: 'Pre-notice consultation · Incoming',
    uploader: 'Ananya Kapoor', origin: 'Global upload', received: '01 Sep 2026 · 08:56 IST',
    destination: 'Apex Auto Components suggested', stage: 'Extraction complete · placement required',
    status: 'Ready', pages: 14, requiresAction: true, summaryLabel: 'Placement decision',
    summaryTitle: 'Choose the owning Matter',
    summaryBody: 'The document is readable and one Matter is strongly supported. Assignment remains a deliberate human decision.',
    findings: [
      { kind: 'placement', label: 'Suggested Matter', value: 'Apex Auto Components · MAT-2024-018', detail: 'Exact Matter code and verified GSTIN agree.', page: 1 },
      { kind: 'deadline', label: 'Possible deadline', value: 'Reply due 18 Sep 2026', detail: 'Extracted date is not yet verified.', page: 4, warning: true },
      { kind: 'financial', label: 'Stated amount', value: 'Proposed tax · ₹14,20,000', detail: 'Allegation context · source-supported.', page: 6 },
    ],
    metadata: [
      { title: 'Document metadata', fields: [
        { label: 'Document type', value: 'FORM GST DRC-01A', page: 1 },
        { label: 'Reference', value: 'DEMO/DRC01A/2026/0142', page: 1, mono: true },
        { label: 'Issue date', value: '31 Aug 2026', page: 1 },
        { label: 'Tax period', value: 'FY 2023–24', page: 2 },
      ] },
      { title: 'Parties and identifiers', fields: [
        { label: 'Issuer', value: 'Illustrative tax authority', page: 1 },
        { label: 'Taxpayer', value: 'Apex Auto Components Private Limited', page: 1 },
        { label: 'GSTIN', value: '27AAECA1234F1Z7', page: 1, mono: true },
      ] },
      { title: 'Dates and financial facts', fields: [
        { label: 'Reply date', value: '18 Sep 2026 · Needs verification', page: 4 },
        { label: 'Proposed tax', value: '₹14,20,000 · Allegation', page: 6, mono: true },
        { label: 'Proposed interest', value: '₹1,18,400 · Allegation', page: 6, mono: true },
      ] },
    ],
    primaryAction: 'Assign document', primaryMutation: true,
  },
  {
    id: 'extracting', name: 'Purchase register reconciliation and annexures FY 2023–24.pdf', classification: 'Supporting evidence · Incoming',
    uploader: 'Rishikesh Joshi', origin: 'Matter upload', received: '01 Sep 2026 · 08:52 IST',
    destination: 'MAT-2024-018', stage: 'Extracting pages 7–18 of 28', status: 'Processing', pages: 28,
    requiresAction: false, summaryLabel: 'Processing status', summaryTitle: 'Reading and extracting document',
    summaryBody: '12 of 28 pages are ready. Processing continues in the background, so you can leave this page.',
    findings: [
      { kind: 'processing', label: 'Current stage', value: 'Extracting', detail: '12 of 28 pages have committed text artifacts.' },
      { kind: 'placement', label: 'Destination', value: 'MAT-2024-018', detail: 'Matter intent was supplied at upload.' },
    ],
    metadata: [{ title: 'Available metadata', fields: [
      { label: 'Document type', value: 'Supporting evidence · provisional' },
      { label: 'Tax period', value: 'FY 2023–24 · provisional', page: 1 },
      { label: 'Pages processed', value: '12 of 28' },
      { label: 'Text source', value: 'Native text with selective OCR' },
    ] }],
    primaryAction: 'View processing details', primaryMutation: false,
  },
  {
    id: 'review', name: 'Order-in-Original 91-2026.pdf', classification: 'Adjudication order · Incoming',
    uploader: 'Meera Shah', origin: 'Global upload', received: '01 Sep 2026 · 08:37 IST',
    destination: 'Placement conflict · 2 Matters', stage: 'Matching stopped for human review', status: 'Review', pages: 31,
    requiresAction: true, summaryLabel: 'Placement conflict', summaryTitle: 'Two Matters have conflicting evidence',
    summaryBody: 'The proceeding reference supports one Matter while the verified GSTIN supports another. Automatic placement is blocked.',
    findings: [
      { kind: 'identity', label: 'Proceeding reference', value: 'OIO/91/2026', detail: 'Matches MAT-2025-044.', page: 1, warning: true },
      { kind: 'identity', label: 'Verified GSTIN', value: '27AAECA1234F1Z7', detail: 'Matches MAT-2024-018.', page: 2, warning: true },
      { kind: 'deadline', label: 'Appeal period', value: 'Three months from service', detail: 'Relative period only; no calendar deadline created.', page: 29 },
    ],
    metadata: [
      { title: 'Document metadata', fields: [
        { label: 'Document type', value: 'Order-in-Original', page: 1 },
        { label: 'Proceeding reference', value: 'OIO/91/2026', page: 1, mono: true },
        { label: 'Issue date', value: '28 Aug 2026', page: 1 },
        { label: 'Appeal period', value: 'Three months from service', page: 29 },
      ] },
      { title: 'Parties and identifiers', fields: [
        { label: 'Issuing authority', value: 'Additional Commissioner', page: 1 },
        { label: 'Taxpayer', value: 'Apex Auto Components Private Limited', page: 2 },
        { label: 'Verified GSTIN', value: '27AAECA1234F1Z7', page: 2, mono: true },
      ] },
      { title: 'Financial facts', fields: [
        { label: 'Confirmed tax', value: '₹14,20,000', page: 24, mono: true },
        { label: 'Interest', value: 'As applicable', page: 24 },
        { label: 'Penalty', value: '₹1,42,000', page: 25, mono: true },
      ] },
    ],
    primaryAction: 'Review conflict', primaryMutation: true,
    claimedBy: 'Ananya Kapoor', claimUntil: '09:25 IST',
  },
  {
    id: 'duplicate', name: 'Signed appeal acknowledgement.pdf', classification: 'Filing acknowledgement · Incoming',
    uploader: 'Rishikesh Joshi', origin: 'Global upload', received: '01 Sep 2026 · 08:19 IST',
    destination: 'Existing record · MAT-2024-018', stage: 'Exact duplicate detected before paid extraction',
    status: 'Duplicate', pages: 3, requiresAction: true, summaryLabel: 'Duplicate match',
    summaryTitle: 'An identical file already exists',
    summaryBody: 'Open the accessible existing record or discard this intake item. No paid extraction was repeated.',
    findings: [
      { kind: 'identity', label: 'Duplicate basis', value: 'Exact file match', detail: 'Content identity was verified before extraction.' },
      { kind: 'placement', label: 'Accessible record', value: 'MAT-2024-018', detail: 'The existing document is available to this fixture role.' },
    ],
    metadata: [{ title: 'Existing record metadata', fields: [
      { label: 'Document type', value: 'Filing acknowledgement', page: 1 },
      { label: 'Acknowledgement', value: 'APL/2026/00814', page: 1, mono: true },
      { label: 'Filed on', value: '30 Aug 2026', page: 1 },
      { label: 'Existing Matter', value: 'MAT-2024-018' },
    ] }],
    primaryAction: 'Open existing document', primaryMutation: false,
  },
  {
    id: 'failed', name: 'Encrypted adjudication order.pdf', classification: 'Classification unavailable',
    uploader: 'Ananya Kapoor', origin: 'Global upload', received: '01 Sep 2026 · 08:00 IST', destination: 'Not assigned',
    stage: 'Validation stopped · password required', status: 'Failed', pages: 0, requiresAction: true,
    summaryLabel: 'File problem', summaryTitle: 'The PDF cannot be read',
    summaryBody: 'The file is password protected. Unlock a local copy and retry; extraction and placement have not run.',
    findings: [
      { kind: 'processing', label: 'Failed stage', value: 'PDF validation', detail: 'Safe error: encrypted document.', warning: true },
      { kind: 'placement', label: 'Placement', value: 'Not evaluated', detail: 'No content was available to matching.' },
    ],
    metadata: [{ title: 'Extraction unavailable', fields: [
      { label: 'Reason', value: 'Password-protected PDF' },
      { label: 'Extracted text', value: 'Not available' },
      { label: 'Page count', value: 'Not available' },
    ] }],
    primaryAction: 'Unlock and retry', primaryMutation: true,
  },
  {
    id: 'ready', name: 'Appeal filing acknowledgement.pdf', classification: 'Filing acknowledgement · Incoming',
    uploader: 'Rishikesh Joshi', origin: 'Matter upload', received: '01 Sep 2026 · 07:00 IST', destination: 'MAT-2024-018',
    stage: 'Assigned · search indexing continues', status: 'Ready', pages: 5, requiresAction: false,
    summaryLabel: 'Document ready', summaryTitle: 'Assigned and available',
    summaryBody: 'The document is part of the Matter record. Search indexing continues independently without blocking access.',
    findings: [
      { kind: 'identity', label: 'Acknowledgement', value: 'APL/2026/00814', detail: 'Native text · exact source.', page: 1 },
      { kind: 'placement', label: 'Owning Matter', value: 'MAT-2024-018', detail: 'Assigned from explicit Matter upload intent.' },
    ],
    metadata: [{ title: 'Document metadata', fields: [
      { label: 'Document type', value: 'Filing acknowledgement', page: 1 },
      { label: 'Acknowledgement', value: 'APL/2026/00814', page: 1, mono: true },
      { label: 'Filed on', value: '30 Aug 2026', page: 1 },
      { label: 'Owning Matter', value: 'MAT-2024-018' },
    ] }],
    primaryAction: 'Open document record', primaryMutation: false,
  },
]

const longContentItem: QueueItem = {
  ...queueItems[0], id: 'long',
  name: 'Consolidated reply with reconciliation annexures, supplier-wise evidence, hearing submissions, corrigendum references, and indexed supporting schedules for FY 2022–23 and FY 2023–24.pdf',
  uploader: 'Harshvardhan Subramanian Venkataraman', received: '31 Aug 2026 · 23:58 IST',
  destination: 'Venkateshwara Industrial Components and Engineering Services Private Limited · MAT-2026-1048 suggested', pages: 186,
}

const filterLabels: Record<QueueFilter, string> = { action: 'Action required', processing: 'Processing', completed: 'Completed', all: 'All statuses' }
const currentUser = 'Rishikesh Joshi'
const paneTransitionMs = 150

function matchesQueueFilter(item: QueueItem, filter: QueueFilter) {
  if (filter === 'all') return true
  if (filter === 'action') return item.requiresAction
  if (filter === 'processing') return item.status === 'Processing'
  return item.status === 'Ready' && !item.requiresAction
}

function statusPresentation(status: QueueStatus) {
  switch (status) {
    case 'Processing': return { variant: 'default' as const, icon: Loader2 }
    case 'Ready': return { variant: 'success' as const, icon: Check }
    case 'Failed': return { variant: 'danger' as const, icon: CircleAlert }
    case 'Review':
    case 'Duplicate': return { variant: 'warning' as const, icon: AlertTriangle }
  }
}

function StatusBadge({ status }: { status: QueueStatus }) {
  const { variant, icon: Icon } = statusPresentation(status)
  return <Badge variant={variant} fixedWidth="xl"><Icon className={cn('size-3.5 shrink-0', status === 'Processing' && 'animate-spin motion-reduce:animate-none')} aria-hidden="true" />{status}</Badge>
}

const processingStages = ['Received', 'Validated', 'Extracting', 'Matching']

function RowProcessingMarker() {
  return <span className="flex min-w-0 items-center gap-1.5" role="status" aria-label="Processing stage: extracting, stage 3 of 4"><span className="grid w-14 shrink-0 grid-cols-4 gap-0.5" aria-hidden="true">{processingStages.map((stage, index) => <span key={stage} className={cn('h-1 rounded-[var(--radius-full)]', index < 2 && 'bg-[var(--success)]', index === 2 && 'animate-pulse bg-[var(--primary)] motion-reduce:animate-none', index > 2 && 'bg-[var(--border-strong)]')} />)}</span><span className="truncate text-[11px] font-medium text-[var(--primary)]">Extracting</span></span>
}

function ReviewClaim({ name }: { name: string }) {
  return <span className="inline-flex min-w-0 max-w-full items-center gap-1.5 text-[11px] font-medium text-[var(--text-secondary)]"><span className="relative flex size-1.5 shrink-0" aria-hidden="true"><span className="absolute inline-flex size-full animate-ping rounded-full bg-[var(--primary)] opacity-25 motion-reduce:animate-none" /><span className="relative inline-flex size-1.5 rounded-full bg-[var(--primary)]" /></span><span className="truncate">{name} reviewing</span></span>
}

function AppRail() {
  return <aside className="hidden h-full w-16 shrink-0 flex-col items-center border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] py-2 text-[var(--sidebar-text)] md:flex" aria-label="Concept navigation"><div className="flex size-10 items-center justify-center text-[var(--sidebar-accent)]"><Gavel className="size-5" /></div><button type="button" aria-label="Today" className="mt-5 flex size-11 items-center justify-center rounded-[var(--radius-sm)] hover:bg-[var(--sidebar-hover)]"><Inbox className="size-5" /></button><button type="button" aria-label="Document Hub" aria-current="page" className="mt-1 flex size-11 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]"><FileText className="size-5" /></button><div className="mt-auto flex size-10 items-center justify-center rounded-full border border-[var(--sidebar-border,var(--border))] text-xs font-semibold">RJ</div></aside>
}

function PreviewMenu({ state, role, onStateChange, onRoleChange }: { state: PreviewState; role: RolePreview; onStateChange: (state: PreviewState) => void; onRoleChange: (role: RolePreview) => void }) {
  return <DropdownMenu><DropdownMenuTrigger asChild><Button variant="outline" size="sm"><FileSearch className="size-4" />Preview<ChevronDown className="size-3.5" /></Button></DropdownMenuTrigger><DropdownMenuContent align="end" className="w-60"><DropdownMenuLabel>Fixture state</DropdownMenuLabel><DropdownMenuRadioGroup value={state} onValueChange={(value) => onStateChange(value as PreviewState)}><DropdownMenuRadioItem value="default">Default queue</DropdownMenuRadioItem><DropdownMenuRadioItem value="upload">Upload tray</DropdownMenuRadioItem><DropdownMenuRadioItem value="loading">Loading</DropdownMenuRadioItem><DropdownMenuRadioItem value="empty">Empty</DropdownMenuRadioItem><DropdownMenuRadioItem value="error">Error</DropdownMenuRadioItem><DropdownMenuRadioItem value="long">Long content</DropdownMenuRadioItem></DropdownMenuRadioGroup><DropdownMenuSeparator /><DropdownMenuLabel>Capability</DropdownMenuLabel><DropdownMenuRadioGroup value={role} onValueChange={(value) => onRoleChange(value as RolePreview)}><DropdownMenuRadioItem value="Associate">Associate · can act</DropdownMenuRadioItem><DropdownMenuRadioItem value="Viewer">Viewer · read only</DropdownMenuRadioItem></DropdownMenuRadioGroup></DropdownMenuContent></DropdownMenu>
}

function GlobalHeader({ state, role, compact, onStateChange, onRoleChange }: { state: PreviewState; role: RolePreview; compact: boolean; onStateChange: (state: PreviewState) => void; onRoleChange: (role: RolePreview) => void }) {
  return <header className={cn('flex h-14 shrink-0 items-center gap-3 border-b border-[var(--border)] bg-[var(--surface)] px-3 md:px-5', compact && 'max-xl:hidden')}><div className="min-w-0 flex-1"><div className="flex min-w-0 items-center gap-2"><span className="hidden truncate text-xs text-[var(--text-muted)] sm:block">Apex Tax Advocates</span><ChevronRight className="hidden size-3 shrink-0 text-[var(--text-muted)] sm:block" /><h1 className="truncate text-lg font-semibold">Document Hub</h1></div><p className="truncate text-[11px] text-[var(--text-muted)]">Organisation intake and document decisions</p></div><Badge variant="outline" className="hidden lg:inline-flex">Fixture concept</Badge><PreviewMenu state={state} role={role} onStateChange={onStateChange} onRoleChange={onRoleChange} /><div className="hidden sm:block"><ThemeToggle /></div><Avatar name="Rishikesh Joshi" size="sm" /></header>
}

function ScopeToggle({ value, onChange }: { value: UploadScope; onChange: (value: UploadScope) => void }) {
  const optionClass = (active: boolean) => cn('border-0 px-3 shadow-none', active ? 'bg-[var(--accent-muted)] font-semibold text-[var(--primary)] hover:bg-[var(--accent-muted)]' : 'text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]')
  return <div className="flex shrink-0 gap-0.5 rounded-[var(--radius-md)] bg-[var(--bg-overlay)] p-1" role="group" aria-label="Upload ownership"><Button variant="ghost" size="sm" className={optionClass(value === 'mine')} aria-pressed={value === 'mine'} onClick={() => onChange('mine')}>My uploads</Button><Button variant="ghost" size="sm" className={optionClass(value === 'all')} aria-pressed={value === 'all'} onClick={() => onChange('all')}>All uploads</Button></div>
}

function StatusFilterMenu({ value, onChange, compact = false }: { value: QueueFilter; onChange: (value: QueueFilter) => void; compact?: boolean }) {
  return <DropdownMenu><DropdownMenuTrigger asChild><button type="button" className={cn('flex min-h-8 items-center gap-1.5 rounded-[var(--radius-sm)] px-1.5 text-xs font-medium text-[var(--text-muted)] outline-none hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)] focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]', compact && 'min-h-10 border border-[var(--border-strong)] px-3 text-[var(--text-primary)]')}><Filter className="size-3.5" aria-hidden="true" /><span>{compact ? filterLabels[value] : 'Status'}</span>{value !== 'all' && !compact && <span className="size-1.5 rounded-full bg-[var(--primary)]" aria-label={`Filtered by ${filterLabels[value]}`} />}<ChevronDown className="size-3.5" aria-hidden="true" /></button></DropdownMenuTrigger><DropdownMenuContent align="start" className="w-56"><DropdownMenuLabel>Status and action state</DropdownMenuLabel><DropdownMenuRadioGroup value={value} onValueChange={(next) => onChange(next as QueueFilter)}>{(Object.entries(filterLabels) as Array<[QueueFilter, string]>).map(([id, label]) => <DropdownMenuRadioItem key={id} value={id}>{label}</DropdownMenuRadioItem>)}</DropdownMenuRadioGroup></DropdownMenuContent></DropdownMenu>
}

function QueueToolbar({ query, scope, filter, count, compact = false, onQuery, onScope, onFilter, onUpload }: { query: string; scope: UploadScope; filter: QueueFilter; count: number | null; compact?: boolean; onQuery: (value: string) => void; onScope: (scope: UploadScope) => void; onFilter: (filter: QueueFilter) => void; onUpload: () => void }) {
  return <div className="min-h-14 shrink-0 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 py-2 sm:px-4"><div className={cn('flex items-center gap-2', compact ? 'flex-nowrap' : 'flex-wrap')}><div className="order-1 shrink-0 sm:order-none"><ScopeToggle value={scope} onChange={onScope} /></div><label className={cn('relative order-2 min-w-0 basis-full sm:order-none sm:w-[min(340px,38vw)] sm:basis-auto', compact && 'order-none min-w-32 flex-1 basis-auto sm:w-auto')}><span className="sr-only">Search document queue</span><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" /><Input value={query} onChange={(event) => onQuery(event.target.value)} placeholder="Search documents" className="pl-9" /></label><div className="order-3 lg:hidden"><StatusFilterMenu value={filter} onChange={onFilter} compact /></div>{!compact && count !== null && <p className="ml-auto hidden text-xs text-[var(--text-muted)] sm:block">{count} {count === 1 ? 'document' : 'documents'}</p>}<Button size="sm" className="order-4 shrink-0 sm:order-none" onClick={onUpload}><Upload className="size-4" />Upload PDFs</Button></div></div>
}

function EmptyQueue({ onUpload }: { onUpload: () => void }) {
  return <section className="flex h-full min-h-0 items-center justify-center overflow-y-auto bg-[var(--bg)] p-5 text-center"><div className="group w-full max-w-xl rounded-[var(--radius-lg)] border border-dashed border-[var(--border-strong)] bg-[var(--surface)] px-6 py-12 shadow-[var(--shadow-xs)] transition-colors hover:border-[var(--primary)] focus-within:border-[var(--primary)] sm:px-12"><div className="relative mx-auto h-20 w-24" aria-hidden="true"><span className="absolute left-2 top-3 h-14 w-11 -rotate-6 rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--bg-overlay)] transition-transform duration-[var(--duration-base)] group-hover:-translate-x-1 group-hover:-rotate-12 motion-reduce:transform-none" /><span className="absolute right-2 top-3 h-14 w-11 rotate-6 rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--bg-overlay)] transition-transform duration-[var(--duration-base)] group-hover:translate-x-1 group-hover:rotate-12 motion-reduce:transform-none" /><span className="absolute inset-x-6 top-0 flex h-16 items-center justify-center rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] text-[var(--primary)] shadow-[var(--shadow-sm)] transition-transform duration-[var(--duration-base)] group-hover:-translate-y-1 motion-reduce:transform-none"><FileText className="size-7" /></span><span className="absolute bottom-0 left-1/2 flex size-8 -translate-x-1/2 items-center justify-center rounded-full bg-[var(--primary)] text-[var(--on-accent)] shadow-[var(--shadow-sm)]"><Upload className="size-4" /></span></div><h2 className="mt-5 text-xl font-semibold">The document queue is empty</h2><p className="mx-auto mt-2 max-w-md text-sm leading-6 text-[var(--text-muted)]">Upload one or more PDFs to begin validation, extraction, matching, and placement. New documents will appear here without changing position unexpectedly.</p><Button className="mt-6" onClick={onUpload}><Upload className="size-4" />Upload PDFs</Button><p className="mt-3 text-xs text-[var(--text-muted)]">You can also drag and drop PDFs anywhere in this workspace.</p></div></section>
}

function ErrorState({ onRetry }: { onRetry: () => void }) {
  return <section className="flex h-full items-center justify-center p-6 text-center"><div className="max-w-sm"><CircleAlert className="mx-auto size-8 text-[var(--danger)]" /><h2 className="mt-4 text-lg font-semibold">The queue could not be displayed</h2><p className="mt-2 text-sm leading-6 text-[var(--text-muted)]">No document data was changed. Try loading the queue again.</p><Button variant="outline" className="mt-5" onClick={onRetry}><RefreshCw className="size-4" />Try again</Button></div></section>
}

function QueueLoading() {
  return <div aria-busy="true" aria-live="polite"><p className="sr-only">Loading document queue…</p><Table className="table-fixed"><TableCaption>Loading document queue.</TableCaption><colgroup><col className="w-[34%]" /><col className="w-[13%]" /><col className="w-[17%]" /><col className="w-[14%]" /><col className="w-[22%]" /></colgroup><TableHeader sticky><TableRow><TableHead>Document</TableHead><TableHead>Status</TableHead><TableHead>Uploaded by</TableHead><TableHead>Source</TableHead><TableHead>Destination</TableHead></TableRow></TableHeader><TableBody>{[1, 2, 3, 4, 5].map((row) => <TableRow key={row} aria-hidden="true"><TableCell><Skeleton className="h-3.5 w-4/5" /><Skeleton className="mt-2 h-3 w-2/5" /></TableCell><TableCell><Skeleton className="h-6 w-24" /></TableCell><TableCell><Skeleton className="h-3.5 w-28" /></TableCell><TableCell><Skeleton className="h-3.5 w-24" /></TableCell><TableCell><Skeleton className="h-3.5 w-4/5" /></TableCell></TableRow>)}</TableBody></Table></div>
}

function DocumentTable({ items, selectedId, condensed, filter, onFilter, onSelect }: { items: QueueItem[]; selectedId: string | null; condensed: boolean; filter: QueueFilter; onFilter: (filter: QueueFilter) => void; onSelect: (item: QueueItem) => void }) {
  return <Table className="table-fixed"><TableCaption>Document queue. Select a row to open its details. Filter by status from the Status column heading.</TableCaption><colgroup>{condensed ? <><col className="w-[48%]" /><col className="w-[20%]" /><col className="w-[32%]" /></> : <><col className="w-[32%]" /><col className="w-[12%]" /><col className="w-[17%]" /><col className="w-[13%]" /><col className="w-[17%]" /><col className="w-[9%]" /></>}</colgroup><TableHeader sticky><TableRow><TableHead>Document</TableHead><TableHead><StatusFilterMenu value={filter} onChange={onFilter} /></TableHead><TableHead>Uploaded by</TableHead>{!condensed && <><TableHead>Source</TableHead><TableHead>Destination</TableHead><TableHead>Received</TableHead></>}</TableRow></TableHeader><TableBody>{items.map((item) => <TableRow key={item.id} interactive selected={selectedId === item.id} tabIndex={0} aria-label={`View details for ${item.name}`} onClick={() => onSelect(item)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(item) } }} className="h-16 cursor-pointer outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]"><TableCell><div className="flex h-12 min-w-0 items-center gap-3"><span className="flex size-8 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] text-[var(--text-muted)]"><FileText className="size-4" /></span><span className="min-w-0"><strong className="block truncate text-sm font-medium" title={item.name}>{item.name}</strong><span className="mt-0.5 flex min-w-0 items-center gap-2">{item.claimedBy ? <ReviewClaim name={item.claimedBy} /> : item.status === 'Processing' && selectedId !== item.id ? <><span className="truncate text-xs text-[var(--text-muted)]">{item.classification.split(' · ')[0]}</span><RowProcessingMarker /></> : <span className="truncate text-xs text-[var(--text-muted)]">{item.classification}</span>}</span></span></div></TableCell><TableCell><StatusBadge status={item.status} /></TableCell><TableCell><span className="flex min-w-0 items-center gap-2"><Avatar name={item.uploader} size="sm" /><span className="min-w-0 truncate text-xs font-medium" title={item.uploader}>{item.uploader}</span></span></TableCell>{!condensed && <><TableCell className="truncate text-xs text-[var(--text-secondary)]">{item.origin}</TableCell><TableCell><span className="block truncate text-xs text-[var(--text-secondary)]" title={item.destination}>{item.destination}</span><span className="mt-0.5 block truncate text-[11px] text-[var(--text-muted)]">{item.stage}</span></TableCell><TableCell className="font-mono text-xs text-[var(--text-secondary)]">{item.received.split(' · ')[0]}</TableCell></>}</TableRow>)}</TableBody></Table>
}

function MobileDocumentList({ items, onSelect }: { items: QueueItem[]; onSelect: (item: QueueItem) => void }) {
  return <div>{items.map((item) => <button key={item.id} type="button" onClick={() => onSelect(item)} className="flex min-h-[88px] w-full items-start gap-3 border-b border-[var(--border-subtle)] px-3 py-3 text-left outline-none hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]"><span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] text-[var(--text-muted)]"><FileText className="size-4" /></span><span className="min-w-0 flex-1"><strong className="block truncate text-sm font-medium">{item.name}</strong><span className="mt-1 flex min-w-0 items-center gap-2">{item.claimedBy ? <ReviewClaim name={item.claimedBy} /> : item.status === 'Processing' ? <RowProcessingMarker /> : <span className="truncate text-xs text-[var(--text-muted)]">{item.destination}</span>}</span><span className="mt-2 flex items-center gap-2 text-xs text-[var(--text-secondary)]"><span className="truncate">{item.uploader}</span><span aria-hidden="true">·</span><span className="truncate">{item.origin}</span></span></span><StatusBadge status={item.status} /></button>)}</div>
}

function FindingIcon({ kind }: { kind: FindingKind }) {
  const Icon = kind === 'deadline' ? CalendarClock : kind === 'financial' ? CircleDollarSign : kind === 'identity' ? Fingerprint : kind === 'placement' ? MapPin : Loader2
  return <Icon className="size-4" />
}

function OverviewSummary({ item }: { item: QueueItem }) {
  const ruleTone = item.status === 'Failed' ? 'border-l-[var(--danger)]' : item.status === 'Review' || item.status === 'Duplicate' ? 'border-l-[var(--warning)]' : item.status === 'Ready' && !item.requiresAction ? 'border-l-[var(--success)]' : 'border-l-[var(--primary)]'
  return <section className="mt-4" aria-label={item.summaryLabel}><div className="flex items-center justify-between gap-3"><h3 className="text-sm font-semibold">{item.summaryLabel}</h3><Badge variant={item.requiresAction ? 'warning' : 'outline'} className="shrink-0">{item.requiresAction ? 'Decision required' : 'No action needed'}</Badge></div><div className={cn('mt-2 border-l-2 pl-3', ruleTone)}><p className="text-sm font-semibold text-[var(--text-primary)]">{item.summaryTitle}</p><p className="mt-1 text-xs leading-4 text-[var(--text-secondary)]">{item.summaryBody}</p></div></section>
}

function OverviewTab({ item, onOpenSource }: { item: QueueItem; onOpenSource: (page: number, label: string) => void }) {
  const intakeFacts = [['Uploaded by', item.uploader], ['Received', item.received], ['Source', item.origin], ['Destination', item.destination], ['Pages', item.pages ? String(item.pages) : 'Not available'], ['Current stage', item.stage]]
  const [documentType, direction] = item.classification.split(' · ')
  return <div className="p-4">
    <section className="min-w-0">
      <div className="flex min-w-0 items-start gap-3"><span className="flex size-10 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--primary)]"><FileText className="size-5" /></span><div className="min-w-0 flex-1"><div className="flex min-w-0 flex-wrap items-center gap-2"><h2 className="break-words text-base font-semibold leading-5">{documentType}</h2>{direction && <Badge variant={direction === 'Outgoing' ? 'outgoing' : 'incoming'}>{direction}</Badge>}</div><p className="mt-1 truncate text-[11px] text-[var(--text-muted)]" title={item.name}>{item.name}</p></div><StatusBadge status={item.status} /></div>
      {item.claimedBy && <div className="mt-3 flex items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--primary)] bg-[var(--accent-muted)] px-3 py-2 text-[var(--primary)]" role="status"><span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-[var(--primary)] text-[var(--on-accent)]"><UserRoundCheck className="size-4" aria-hidden="true" /></span><div className="min-w-0"><p className="truncate text-xs font-semibold">{item.claimedBy} is reviewing</p><p className="mt-0.5 text-[11px] text-[var(--text-secondary)]">Reserved until {item.claimUntil} · Evidence remains available to inspect</p></div></div>}
    </section>
    <section aria-labelledby={`evidence-${item.id}`} className="mt-4">
      <div className="flex items-baseline justify-between gap-3"><h3 id={`evidence-${item.id}`} className="text-sm font-semibold">{item.status === 'Processing' ? 'Processing details' : 'Key evidence'}</h3><span className="text-[11px] text-[var(--text-muted)]">{item.findings.length} {item.status === 'Processing' ? 'details' : 'surfaced'}</span></div>
      <div className="mt-2 divide-y divide-[var(--border-subtle)] border-y border-[var(--border-subtle)]">{item.findings.map((finding) => <div key={`${finding.label}-${finding.value}`} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3 py-2.5"><div className="flex min-w-0 items-start gap-2.5"><span className={cn('mt-0.5 text-[var(--text-muted)]', finding.warning && 'text-[var(--warning)]')}><FindingIcon kind={finding.kind} /></span><div className="min-w-0"><p className="text-[11px] font-medium text-[var(--text-secondary)]">{finding.label}</p><p className="mt-0.5 break-words text-sm font-semibold">{finding.value}</p><p className="mt-0.5 text-[11px] leading-4 text-[var(--text-muted)]">{finding.detail}</p></div></div>{finding.page && <Button variant="link" size="sm" className="min-h-10 shrink-0 px-1" onClick={() => onOpenSource(finding.page!, finding.label)}><Highlighter className="size-3.5" />Page {finding.page}</Button>}</div>)}</div>
    </section>
    <OverviewSummary item={item} />
    <section aria-labelledby={`intake-${item.id}`} className="mt-4">
      <h3 id={`intake-${item.id}`} className="text-sm font-semibold">Intake details</h3>
      <dl className="mt-2 grid grid-cols-2 gap-px overflow-hidden rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--border-subtle)]">{intakeFacts.map(([label, value]) => <div key={label} className="min-w-0 bg-[var(--surface)] px-2.5 py-2"><dt className="text-[10px] font-medium uppercase tracking-wide text-[var(--text-muted)]">{label}</dt><dd className="mt-0.5 break-words text-xs font-medium leading-4 text-[var(--text-secondary)]">{value}</dd></div>)}</dl>
    </section>
  </div>
}

function ExtractedTab({ item, onOpenSource }: { item: QueueItem; onOpenSource: (page: number, label: string) => void }) {
  return <div className="p-4">
    <div className="flex items-start gap-2.5 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--accent-muted)] px-3 py-2.5"><span className="flex size-8 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--surface)] text-[var(--primary)]"><FileSearch className="size-4" aria-hidden="true" /></span><div className="min-w-0"><p className="text-xs font-semibold text-[var(--text-primary)]">AI-extracted values</p><p className="mt-0.5 text-[11px] leading-4 text-[var(--text-secondary)]">Verify dates, amounts, and identifiers against each linked source before relying on them.</p></div></div>
    <div className="mt-4 space-y-4">{item.metadata.map((section) => {
      const sectionId = `${item.id}-${section.title.replaceAll(' ', '-')}`
      return <section key={section.title} aria-labelledby={sectionId} className="overflow-hidden rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface)]"><header className="flex min-h-10 items-center justify-between gap-3 border-b border-[var(--border-subtle)] bg-[var(--bg)] px-3"><h3 id={sectionId} className="text-xs font-semibold">{section.title}</h3><span className="text-[10px] font-medium text-[var(--text-muted)]">{section.fields.length} {section.fields.length === 1 ? 'field' : 'fields'}</span></header><dl className="grid grid-cols-2 gap-px bg-[var(--border-subtle)]">{section.fields.map((field, index) => <div key={`${section.title}-${field.label}`} className={cn('min-w-0 bg-[var(--surface)] px-3 py-2.5', section.fields.length % 2 === 1 && index === section.fields.length - 1 && 'col-span-2')}><dt className="text-[10px] font-medium uppercase tracking-wide text-[var(--text-muted)]">{field.label}</dt><dd className="mt-1 min-w-0 text-xs font-semibold leading-4 text-[var(--text-primary)]"><span className={cn('break-words', field.mono && 'font-mono')}>{field.value}</span>{field.page && <Button variant="link" size="sm" className="mt-1 flex min-h-7 justify-start px-0 text-[11px]" onClick={() => onOpenSource(field.page!, field.label)}><Highlighter className="size-3" />Page {field.page}</Button>}</dd></div>)}</dl></section>
    })}</div>
  </div>
}

function DetailSidebarTabs({ tab, count, collapsible = false, open = true, onTabChange, onClose, className }: { tab: DetailTab; count: number; collapsible?: boolean; open?: boolean; onTabChange: (tab: DetailTab) => void; onClose: () => void; className?: string }) {
  return <div className={cn('flex h-14 shrink-0 items-stretch border-b border-[var(--border-subtle)] bg-[var(--surface)] px-2', collapsible && 'overflow-hidden border-l border-[var(--border)] transition-[width,min-width,max-width,opacity,transform] duration-[var(--duration-fast)] ease-[var(--ease-smooth)] motion-reduce:transition-none', collapsible && (open ? 'w-[40%] min-w-[430px] max-w-[580px] translate-x-0 opacity-100' : 'pointer-events-none w-0 min-w-0 max-w-0 translate-x-3 border-l-0 px-0 opacity-0'), className)} role="tablist" aria-label="Document sidebar sections"><button type="button" role="tab" aria-selected={tab === 'overview'} aria-controls="document-overview-panel" onClick={() => onTabChange('overview')} className={cn('relative flex min-w-0 items-center gap-2 px-3 text-sm font-medium outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]', tab === 'overview' ? 'text-[var(--text-primary)] after:absolute after:inset-x-3 after:bottom-0 after:h-0.5 after:bg-[var(--primary)]' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]')}><FileText className="size-4" />Overview</button><button type="button" role="tab" aria-selected={tab === 'extracted'} aria-controls="document-extracted-panel" onClick={() => onTabChange('extracted')} className={cn('relative flex min-w-0 items-center gap-2 px-3 text-sm font-medium outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]', tab === 'extracted' ? 'text-[var(--text-primary)] after:absolute after:inset-x-3 after:bottom-0 after:h-0.5 after:bg-[var(--primary)]' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]')}><FileSearch className="size-4" />Extracted data <span className="text-[11px] text-[var(--text-muted)]">{count}</span></button><Button variant="ghost" size="icon" className="ml-auto self-center" onClick={onClose} aria-label="Close document sidebar" title="Close document sidebar"><X className="size-4" /></Button></div>
}

function DetailSidebar({ item, role, tab, mobile, headerless = false, open = true, onTabChange, onClose, onOpenSource, onViewOriginal, onPrimary }: { item: QueueItem; role: RolePreview; tab: DetailTab; mobile?: boolean; headerless?: boolean; open?: boolean; onTabChange: (tab: DetailTab) => void; onClose: () => void; onOpenSource: (page: number, label: string) => void; onViewOriginal: () => void; onPrimary: () => void }) {
  const claimedElsewhere = Boolean(item.claimedBy && item.claimedBy !== currentUser)
  const primaryDisabled = (role === 'Viewer' && item.primaryMutation) || claimedElsewhere
  const count = item.metadata.reduce((total, section) => total + section.fields.length, 0)
  return <aside aria-label={`Document details for ${item.name}`} className={cn('flex h-full min-h-0 flex-col border-l border-[var(--border)] bg-[var(--surface)] transition-[width,min-width,max-width,opacity,transform] duration-[var(--duration-fast)] ease-[var(--ease-smooth)] motion-reduce:transition-none', mobile ? open ? 'translate-x-0 opacity-100' : 'pointer-events-none translate-x-3 opacity-0' : open ? 'w-[40%] min-w-[430px] max-w-[580px] shrink-0 translate-x-0 opacity-100' : 'pointer-events-none w-0 min-w-0 max-w-0 shrink-0 translate-x-3 overflow-hidden border-l-0 opacity-0')}>{mobile && <div className="flex h-12 shrink-0 items-center border-b border-[var(--border-subtle)] px-2"><Button variant="ghost" size="sm" onClick={onClose}><ArrowLeft className="size-4" />Back to documents</Button></div>}{!headerless && <DetailSidebarTabs tab={tab} count={count} onTabChange={onTabChange} onClose={onClose} />}<div id={`document-${tab}-panel`} role="tabpanel" className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain" style={{ scrollbarGutter: 'stable' }}>{tab === 'overview' ? <OverviewTab item={item} onOpenSource={onOpenSource} /> : <ExtractedTab item={item} onOpenSource={onOpenSource} />}</div><footer className="shrink-0 border-t border-[var(--border-subtle)] bg-[var(--surface)] p-3"><div className="flex flex-col gap-2 sm:flex-row sm:justify-end"><Button variant="outline" onClick={onViewOriginal} disabled={item.pages === 0}><FileSearch className="size-4" />View original PDF</Button><Button onClick={onPrimary} disabled={primaryDisabled}>{claimedElsewhere ? 'Review in progress' : item.primaryAction}</Button></div>{claimedElsewhere ? <p className="mt-2 text-right text-[11px] text-[var(--text-muted)]">{item.claimedBy} has the active review until {item.claimUntil}. You can still inspect the evidence.</p> : primaryDisabled && <p className="mt-2 text-right text-[11px] text-[var(--text-muted)]">Viewer access cannot perform this action.</p>}</footer></aside>
}

function PdfPage({ item, page, highlighted, highlightLabel, onQuote }: { item: QueueItem; page: number; highlighted: boolean; highlightLabel: string | null; onQuote: () => void }) {
  return <article className="mx-auto mb-5 min-h-[680px] w-[min(760px,calc(100%-2rem))] bg-[var(--surface)] p-10 text-[var(--text-primary)] shadow-[var(--shadow-sm)] ring-1 ring-[var(--border)] sm:p-14"><p className="text-center text-[10px] font-semibold uppercase tracking-[0.13em] text-[var(--text-muted)]">Readable page placeholder · fixture only</p><h3 className="mt-12 text-center text-lg font-semibold">{item.classification.split(' · ')[0]}</h3><p className="mt-2 text-center font-mono text-xs text-[var(--text-muted)]">Source page {page} of {item.pages}</p><div className="mt-12 grid grid-cols-[140px_1fr] gap-x-5 gap-y-3 border-y border-[var(--border-subtle)] py-5 text-xs"><span className="text-[var(--text-muted)]">Document</span><span className="font-medium">{item.name}</span><span className="text-[var(--text-muted)]">Matter context</span><span className="font-mono">{item.destination}</span></div><div className="mt-10 space-y-5 text-sm leading-7 text-[var(--text-secondary)]"><p>1. This fictional passage demonstrates the original document view without representing a real legal record or uploaded file.</p><button type="button" onClick={onQuote} className={cn('w-full rounded-[var(--radius-sm)] border p-4 text-left outline-none transition-colors focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]', highlighted ? 'border-[var(--primary)] bg-[var(--accent-muted)] text-[var(--text-primary)] shadow-[var(--shadow-xs)]' : 'border-transparent hover:border-[var(--border)] hover:bg-[var(--bg)]')}><span className="flex flex-col items-start gap-2 sm:flex-row sm:items-center sm:justify-between"><span>2. The cited statement remains anchored to this immutable source page and can be compared with extracted metadata.</span>{highlighted && <Badge variant="default" className="shrink-0"><Highlighter className="size-3" />Cited passage</Badge>}</span><span className="mt-2 flex items-center gap-1 text-xs font-medium text-[var(--primary)]"><Highlighter className="size-3.5" />{highlighted && highlightLabel ? `Source for ${highlightLabel}` : 'Preview quotation from this passage'}</span></button><p>3. In production, retained page coordinates place the highlight over the exact cited region. Text anchoring is used as a fallback when coordinates are unavailable.</p></div><p className="mt-28 text-center font-mono text-[11px] text-[var(--text-muted)]">Fixture page {page} of {item.pages}</p></article>
}

function ViewerToolbar({ item, source, onSourceChange, onClose, className }: { item: QueueItem; source: SourceContext; onSourceChange: (source: SourceContext) => void; onClose: () => void; className?: string }) {
  const changePage = (page: number) => onSourceChange({ page: Math.max(1, Math.min(item.pages, page)), label: null })
  return <div className={cn('flex h-14 shrink-0 items-center gap-2 border-b border-[var(--border)] bg-[var(--surface)] px-2 sm:px-3', className)}><div className="mr-auto hidden min-w-0 items-center gap-2 lg:flex"><FileText className="size-4 shrink-0 text-[var(--text-muted)]" /><span className="max-w-64 truncate text-xs font-medium" title={item.name}>{item.name}</span></div><Button variant="ghost" size="icon" onClick={() => changePage(source.page - 1)} aria-label="Previous page"><ChevronLeft className="size-4" /></Button><span className="text-xs text-[var(--text-muted)]">Page</span><Input aria-label="Current page" value={source.page} onChange={(event) => changePage(Number(event.target.value) || 1)} className="h-9 w-12 px-2 text-center font-mono" /><span className="text-xs text-[var(--text-muted)]">/ {item.pages}</span><Button variant="ghost" size="icon" onClick={() => changePage(source.page + 1)} aria-label="Next page"><ChevronRight className="size-4" /></Button><span className="mx-1 hidden h-5 w-px bg-[var(--border)] sm:block" /><div className="hidden items-center sm:flex"><Button variant="ghost" size="icon" aria-label="Zoom out"><ZoomOut className="size-4" /></Button><span className="w-12 text-center font-mono text-xs text-[var(--text-muted)]">100%</span><Button variant="ghost" size="icon" aria-label="Zoom in"><ZoomIn className="size-4" /></Button><Button variant="ghost" size="icon" aria-label="Rotate page"><RotateCw className="size-4" /></Button></div><Button variant="ghost" size="icon" className="ml-1" onClick={onClose} aria-label="Close PDF viewer" title="Close PDF viewer"><X className="size-5" /></Button></div>
}

function ViewerPane({ item, source, desktopToolbarExternal = false, onSourceChange, onClose, onQuote }: { item: QueueItem; source: SourceContext; desktopToolbarExternal?: boolean; onSourceChange: (source: SourceContext) => void; onClose: () => void; onQuote: () => void }) {
  return <section aria-label={`Original PDF for ${item.name}`} className="flex h-full min-h-0 min-w-0 flex-1 flex-col bg-[var(--bg-overlay)]"><ViewerToolbar item={item} source={source} onSourceChange={onSourceChange} onClose={onClose} className={cn(desktopToolbarExternal && 'xl:hidden')} />{source.label && <div className="flex min-h-9 shrink-0 items-center gap-2 border-b border-[var(--border)] bg-[var(--accent-muted)] px-3 text-xs text-[var(--text-secondary)]"><Highlighter className="size-3.5 text-[var(--primary)]" /><span>Showing cited source for <strong>{source.label}</strong> on page {source.page}</span></div>}<div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain py-5" style={{ scrollbarGutter: 'stable' }}><PdfPage item={item} page={source.page} highlighted={Boolean(source.label)} highlightLabel={source.label} onQuote={onQuote} />{source.page < item.pages && <PdfPage item={item} page={source.page + 1} highlighted={false} highlightLabel={null} onQuote={onQuote} />}</div></section>
}

function UploadTray({ onClose }: { onClose: () => void }) {
  return <aside aria-label="Upload tray fixture" className="absolute inset-x-2 bottom-2 z-40 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] shadow-[var(--shadow-xl)] sm:left-auto sm:w-[430px]"><header className="flex min-h-12 items-center gap-2 border-b border-[var(--border)] px-3"><Upload className="size-4 text-[var(--primary)]" /><div><h2 className="text-sm font-semibold">Uploading 2 PDFs</h2><p className="text-[11px] text-[var(--text-muted)]">Fixture values · no files leave this concept</p></div><Button variant="ghost" size="icon" className="ml-auto" onClick={onClose} aria-label="Close upload tray"><X className="size-4" /></Button></header><div className="divide-y divide-[var(--border-subtle)]"><div className="p-3"><div className="flex items-start gap-3"><FileText className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" /><div className="min-w-0 flex-1"><div className="flex gap-3 text-xs"><span className="min-w-0 flex-1 truncate font-medium">Reply and annexures.pdf</span><span className="shrink-0 font-mono text-[var(--text-muted)]">7.8 / 12.4 MB</span></div><div className="mt-2 h-1.5 overflow-hidden rounded-[var(--radius-full)] bg-[var(--bg-overlay)]" role="progressbar" aria-label="Reply and annexures upload progress" aria-valuemin={0} aria-valuemax={100} aria-valuenow={63}><div className="h-full w-[63%] rounded-[var(--radius-full)] bg-[var(--primary)]" /></div></div><Button variant="ghost" size="sm">Cancel</Button></div></div><div className="flex items-center gap-3 p-3"><CheckCircle2 className="size-4 shrink-0 text-[var(--success)]" /><div className="min-w-0 flex-1"><div className="truncate text-xs font-medium">Hearing notice.pdf</div><div className="text-[11px] text-[var(--text-muted)]">Transferred · validating</div></div><Badge variant="default"><Loader2 className="size-3 animate-spin motion-reduce:animate-none" />Validating</Badge></div></div></aside>
}

export function DocumentHubWorkbenchConcept() {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [detailTab, setDetailTab] = useState<DetailTab>('overview')
  const [mobileDetail, setMobileDetail] = useState(false)
  const [source, setSource] = useState<SourceContext | null>(null)
  const [query, setQuery] = useState('')
  const [activeFilter, setActiveFilter] = useState<QueueFilter>('all')
  const [uploadScope, setUploadScope] = useState<UploadScope>('mine')
  const [previewState, setPreviewState] = useState<PreviewState>('default')
  const [role, setRole] = useState<RolePreview>('Associate')
  const [trayOpen, setTrayOpen] = useState(false)
  const [announcement, setAnnouncement] = useState('')
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const closeTimerRef = useRef<number | null>(null)

  const allItems = useMemo(() => previewState === 'long' ? [longContentItem, ...queueItems] : queueItems, [previewState])
  const selected = allItems.find((item) => item.id === selectedId) ?? null
  const items = useMemo(() => allItems.filter((item) => {
    const haystack = `${item.name} ${item.uploader} ${item.origin} ${item.destination} ${item.classification}`.toLowerCase()
    const matchesScope = uploadScope === 'all' || item.uploader === currentUser
    return matchesScope && haystack.includes(query.trim().toLowerCase()) && matchesQueueFilter(item, activeFilter)
  }), [activeFilter, allItems, query, uploadScope])

  const openNativePicker = () => fileInputRef.current?.click()
  const showUploadFixture = () => { setTrayOpen(true); setPreviewState('default'); setAnnouncement('Fixture upload started. No files leave this local concept.') }
  const clearScheduledClose = () => { if (closeTimerRef.current !== null) { window.clearTimeout(closeTimerRef.current); closeTimerRef.current = null } }
  const revealSidebar = () => { window.requestAnimationFrame(() => setSidebarOpen(true)) }
  const selectDesktop = (item: QueueItem) => { clearScheduledClose(); const shouldReveal = !selectedId || !sidebarOpen; setSelectedId(item.id); setDetailTab('overview'); setSource(null); setMobileDetail(false); if (shouldReveal) { setSidebarOpen(false); revealSidebar() } }
  const selectMobile = (item: QueueItem) => { clearScheduledClose(); const shouldReveal = !selectedId || !sidebarOpen; setSelectedId(item.id); setDetailTab('overview'); setSource(null); setMobileDetail(true); if (shouldReveal) { setSidebarOpen(false); revealSidebar() } }
  const closeDetails = () => { clearScheduledClose(); setSidebarOpen(false); const closeDelay = window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : paneTransitionMs; closeTimerRef.current = window.setTimeout(() => { setSelectedId(null); setDetailTab('overview'); setSource(null); setMobileDetail(false); closeTimerRef.current = null }, closeDelay) }
  const openOriginal = () => { if (selected?.pages) setSource({ page: 1, label: null }) }
  const openCitedSource = (page: number, label: string) => { setSource({ page, label }); setAnnouncement(`Opened source page ${page} with the ${label} citation highlighted.`) }
  const closeViewer = () => { setSource(null); setAnnouncement('Returned to the document queue with details preserved.') }
  const changePreview = (state: PreviewState) => { clearScheduledClose(); setPreviewState(state); setSidebarOpen(false); setSelectedId(null); setDetailTab('overview'); setSource(null); setMobileDetail(false); if (state === 'upload') setTrayOpen(true) }

  const queueBody = previewState === 'loading' ? <QueueLoading /> : previewState === 'error' ? <ErrorState onRetry={() => changePreview('default')} /> : items.length === 0 ? <section className="flex h-full items-center justify-center p-6 text-center"><div><Search className="mx-auto size-7 text-[var(--text-muted)]" /><h2 className="mt-3 text-base font-semibold">No matching documents</h2><p className="mt-1 text-sm text-[var(--text-muted)]">Clear the search or choose a broader queue view.</p></div></section> : <><div className="hidden xl:block"><DocumentTable items={items} selectedId={selectedId} condensed={sidebarOpen} filter={activeFilter} onFilter={setActiveFilter} onSelect={selectDesktop} /></div><div className="xl:hidden"><MobileDocumentList items={items} onSelect={selectMobile} /></div></>
  const queueCount = previewState === 'loading' || previewState === 'error' ? null : items.length
  const selectedFieldCount = selected?.metadata.reduce((total, section) => total + section.fields.length, 0) ?? 0

  return <div className="relative flex h-dvh min-w-0 overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]">
    <AppRail />
    <div className="relative flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden">
      <input ref={fileInputRef} type="file" accept="application/pdf,.pdf" multiple hidden tabIndex={-1} aria-hidden="true" onChange={showUploadFixture} />
      <GlobalHeader state={previewState} role={role} compact={mobileDetail || Boolean(source)} onStateChange={changePreview} onRoleChange={setRole} />

      {previewState !== 'empty' && !selected && <QueueToolbar query={query} scope={uploadScope} filter={activeFilter} count={queueCount} onQuery={setQuery} onScope={setUploadScope} onFilter={setActiveFilter} onUpload={openNativePicker} />}
      {previewState !== 'empty' && selected && !source && !mobileDetail && <div className="xl:hidden"><QueueToolbar query={query} scope={uploadScope} filter={activeFilter} count={queueCount} onQuery={setQuery} onScope={setUploadScope} onFilter={setActiveFilter} onUpload={openNativePicker} /></div>}
      {previewState !== 'empty' && selected && <div className="hidden h-14 shrink-0 xl:flex">
        <div className="min-w-0 flex-1">{source ? <ViewerToolbar item={selected} source={source} onSourceChange={setSource} onClose={closeViewer} /> : <QueueToolbar query={query} scope={uploadScope} filter={activeFilter} count={queueCount} compact onQuery={setQuery} onScope={setUploadScope} onFilter={setActiveFilter} onUpload={openNativePicker} />}</div>
        <DetailSidebarTabs tab={detailTab} count={selectedFieldCount} collapsible open={sidebarOpen} onTabChange={setDetailTab} onClose={closeDetails} />
      </div>}

      <main className="relative min-h-0 flex-1 overflow-hidden">
        {previewState === 'empty' ? <EmptyQueue onUpload={openNativePicker} /> : <>
          <div className="hidden h-full min-h-0 xl:flex">
            <section aria-label={source && selected ? `PDF workspace for ${selected.name}` : 'Document queue'} className="min-w-0 flex-1 overflow-hidden bg-[var(--surface)]">
              {source && selected ? <ViewerPane item={selected} source={source} desktopToolbarExternal onSourceChange={setSource} onClose={closeViewer} onQuote={() => setAnnouncement('Quotation preview selected. No note was created.')} /> : <div className="custom-scrollbar h-full min-h-0 overflow-y-auto overscroll-contain" style={{ scrollbarGutter: 'stable' }}>{queueBody}</div>}
            </section>
            {selected && <DetailSidebar item={selected} role={role} tab={detailTab} headerless open={sidebarOpen} onTabChange={setDetailTab} onClose={closeDetails} onOpenSource={openCitedSource} onViewOriginal={openOriginal} onPrimary={() => setAnnouncement(`${selected.primaryAction} preview complete. No production command ran.`)} />}
          </div>
          <div className="h-full min-h-0 xl:hidden">
            {source && selected ? <ViewerPane item={selected} source={source} onSourceChange={setSource} onClose={closeViewer} onQuote={() => setAnnouncement('Quotation preview selected. No note was created.')} /> : mobileDetail && selected ? <DetailSidebar mobile item={selected} role={role} tab={detailTab} open={sidebarOpen} onTabChange={setDetailTab} onClose={closeDetails} onOpenSource={openCitedSource} onViewOriginal={openOriginal} onPrimary={() => setAnnouncement(`${selected.primaryAction} preview complete. No production command ran.`)} /> : <section aria-label="Document queue" className="custom-scrollbar h-full min-h-0 overflow-y-auto overscroll-contain bg-[var(--surface)]">{queueBody}</section>}
          </div>
        </>}
      </main>
      {trayOpen && <UploadTray onClose={() => setTrayOpen(false)} />}
      <p className="sr-only" aria-live="polite">{announcement}</p>
    </div>
  </div>
}
