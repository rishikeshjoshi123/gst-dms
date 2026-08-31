'use client'

import { useMemo, useRef, useState } from 'react'
import {
  AlertTriangle,
  ArrowLeft,
  BookOpen,
  Check,
  CheckCircle2,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  Copy,
  Download,
  FileCheck2,
  FileSearch,
  FileText,
  Filter,
  Highlighter,
  Info,
  ListFilter,
  Loader2,
  LockKeyhole,
  MessageSquareText,
  MoreHorizontal,
  PanelRightOpen,
  Plus,
  RefreshCw,
  RotateCw,
  Search,
  ShieldCheck,
  Upload,
  X,
  ZoomIn,
  ZoomOut,
} from 'lucide-react'

import { ThemeToggle } from '@/components/nav/ThemeToggle'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { cn } from '@/lib/utils'

type PreviewState = 'default' | 'upload' | 'loading' | 'empty' | 'error' | 'long'
type QueueFilter = 'Needs action' | 'In progress' | 'Recent' | 'All'
type QueueStatus = 'Extracting' | 'Needs placement' | 'Review' | 'Duplicate' | 'Failed' | 'Ready'
type RolePreview = 'Associate' | 'Viewer'
type WorkbenchMode = 'document' | 'details' | 'notes' | 'placement'

type QueueItem = {
  id: string
  name: string
  source: string
  destination: string
  detail: string
  age: string
  status: QueueStatus
  action: string
  pages: number
}

const queueItems: QueueItem[] = [
  {
    id: 'placement',
    name: 'DRC-01A notice — August 2026.pdf',
    source: 'Global upload · Ananya Kapoor',
    destination: 'Suggested: Apex Auto Components',
    detail: 'One exact matter code and GSTIN agree',
    age: '4 min',
    status: 'Needs placement',
    action: 'Choose matter',
    pages: 14,
  },
  {
    id: 'extracting',
    name: 'Purchase register reconciliation and supporting annexures FY 2023–24.pdf',
    source: 'Matter upload · Rishikesh Joshi',
    destination: 'Apex Auto Components · MAT-2024-018',
    detail: 'Running OCR on pages 7–18',
    age: '8 min',
    status: 'Extracting',
    action: 'View progress',
    pages: 28,
  },
  {
    id: 'review',
    name: 'Order-in-Original 91-2026.pdf',
    source: 'Global upload · Meera Shah',
    destination: 'Placement conflict · 2 matters',
    detail: 'Reference and verified GSTIN point to different matters',
    age: '23 min',
    status: 'Review',
    action: 'Review conflict',
    pages: 31,
  },
  {
    id: 'duplicate',
    name: 'Signed appeal acknowledgement.pdf',
    source: 'Global upload · Rishikesh Joshi',
    destination: 'Existing document · MAT-2024-018',
    detail: 'Exact file already exists in the active matter',
    age: '41 min',
    status: 'Duplicate',
    action: 'Open existing',
    pages: 3,
  },
  {
    id: 'failed',
    name: 'Encrypted adjudication order.pdf',
    source: 'Global upload · Ananya Kapoor',
    destination: 'Not placed',
    detail: 'Password-protected PDF could not be read',
    age: '1 hr',
    status: 'Failed',
    action: 'Unlock and retry',
    pages: 0,
  },
  {
    id: 'ready',
    name: 'Appeal filing acknowledgement.pdf',
    source: 'Matter upload · Rishikesh Joshi',
    destination: 'Apex Auto Components · MAT-2024-018',
    detail: 'Assigned · Search indexing continues separately',
    age: '2 hr',
    status: 'Ready',
    action: 'Open document',
    pages: 5,
  },
]

const longContentItem: QueueItem = {
  id: 'long',
  name: 'Consolidated reply with reconciliation annexures, supplier-wise evidence, hearing submissions, corrigendum references, and indexed supporting schedules for FY 2022–23 and FY 2023–24.pdf',
  source: 'Global upload · A team member whose display name is intentionally very long',
  destination: 'Suggested: Venkateshwara Industrial Components and Engineering Services Private Limited · MAT-2026-1048',
  detail: 'Possible reference match differs by one OCR character; financial year and issuer overlap are suggestion evidence only',
  age: 'Yesterday at 23:58',
  status: 'Needs placement',
  action: 'Choose matter',
  pages: 186,
}

const filters: QueueFilter[] = ['Needs action', 'In progress', 'Recent', 'All']

function matchesQueueFilter(item: QueueItem, filter: QueueFilter) {
  if (filter === 'All') return true
  if (filter === 'In progress') return item.status === 'Extracting'
  if (filter === 'Recent') return item.status === 'Ready'
  return ['Needs placement', 'Review', 'Duplicate', 'Failed'].includes(item.status)
}

function statusPresentation(status: QueueStatus) {
  switch (status) {
    case 'Extracting':
      return { variant: 'default' as const, icon: Loader2 }
    case 'Ready':
      return { variant: 'success' as const, icon: Check }
    case 'Failed':
      return { variant: 'danger' as const, icon: CircleAlert }
    case 'Needs placement':
    case 'Review':
    case 'Duplicate':
      return { variant: 'warning' as const, icon: AlertTriangle }
  }
}

function StatusBadge({ status }: { status: QueueStatus }) {
  const { variant, icon: Icon } = statusPresentation(status)
  return (
    <Badge variant={variant} fixedWidth="xl">
      <Icon className={cn('size-3.5 shrink-0', status === 'Extracting' && 'animate-spin motion-reduce:animate-none')} aria-hidden="true" />
      {status}
    </Badge>
  )
}

function FixtureMenu({ state, onStateChange }: { state: PreviewState; onStateChange: (state: PreviewState) => void }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm">
          <FileSearch className="size-4" /> Preview state <ChevronDown className="size-3.5" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        <DropdownMenuLabel>Fixture-only states</DropdownMenuLabel>
        <DropdownMenuRadioGroup value={state} onValueChange={(value) => onStateChange(value as PreviewState)}>
          <DropdownMenuRadioItem value="default">Default queue</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="upload">Upload tray</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="loading">Loading</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="empty">Empty</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="error">Error</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="long">Long content</DropdownMenuRadioItem>
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function RoleMenu({ role, onRoleChange }: { role: RolePreview; onRoleChange: (role: RolePreview) => void }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm">
          {role === 'Viewer' ? <LockKeyhole className="size-4" /> : <ShieldCheck className="size-4" />}
          {role} preview <ChevronDown className="size-3.5" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-52">
        <DropdownMenuLabel>Capability preview</DropdownMenuLabel>
        <DropdownMenuRadioGroup value={role} onValueChange={(value) => onRoleChange(value as RolePreview)}>
          <DropdownMenuRadioItem value="Associate">Associate · can place</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="Viewer">Viewer · read only</DropdownMenuRadioItem>
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function UploadTray({ onClose }: { onClose: () => void }) {
  return (
    <aside
      aria-label="Upload tray fixture"
      className="absolute inset-x-2 bottom-2 z-40 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] shadow-[var(--shadow-xl)] sm:left-auto sm:w-[430px]"
    >
      <header className="flex min-h-12 items-center gap-2 border-b border-[var(--border)] px-3">
        <Upload className="size-4 text-[var(--primary)]" aria-hidden="true" />
        <div>
          <h2 className="text-sm font-semibold">Uploading 2 PDFs</h2>
          <p className="text-[11px] text-[var(--text-muted)]">Fixture values · no files leave this browser concept</p>
        </div>
        <Button variant="ghost" size="icon" className="ml-auto" onClick={onClose} aria-label="Close upload tray">
          <X className="size-4" />
        </Button>
      </header>
      <div className="divide-y divide-[var(--border-subtle)]">
        <div className="p-3">
          <div className="flex items-start gap-3">
            <FileText className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" />
            <div className="min-w-0 flex-1">
              <div className="flex gap-3 text-xs"><span className="min-w-0 flex-1 truncate font-medium">Reply and annexures.pdf</span><span className="shrink-0 font-mono text-[var(--text-muted)]">7.8 / 12.4 MB</span></div>
              <div className="mt-2 h-1.5 overflow-hidden rounded-[var(--radius-full)] bg-[var(--bg-overlay)]" role="progressbar" aria-label="Reply and annexures upload progress" aria-valuemin={0} aria-valuemax={100} aria-valuenow={63}>
                <div className="h-full w-[63%] rounded-[var(--radius-full)] bg-[var(--primary)]" />
              </div>
            </div>
            <Button variant="ghost" size="sm">Cancel</Button>
          </div>
        </div>
        <div className="flex items-center gap-3 p-3">
          <CheckCircle2 className="size-4 shrink-0 text-[var(--success)]" />
          <div className="min-w-0 flex-1"><div className="truncate text-xs font-medium">Hearing notice.pdf</div><div className="text-[11px] text-[var(--text-muted)]">Transferred · finalizing durable queue item</div></div>
          <Badge variant="default" fixedWidth="md"><Loader2 className="size-3 animate-spin motion-reduce:animate-none" />Validating</Badge>
        </div>
      </div>
    </aside>
  )
}

function QueueLoading() {
  return (
    <div className="divide-y divide-[var(--border-subtle)]" role="status" aria-label="Loading document queue">
      <span className="sr-only">Loading document queue</span>
      {[0, 1, 2, 3].map((item) => (
        <div key={item} className="space-y-3 p-4" aria-hidden="true">
          <div className="flex items-center gap-3"><Skeleton className="h-4 flex-1" /><Skeleton className="h-6 w-32" /></div>
          <Skeleton className="h-3 w-4/5" />
          <div className="flex items-center justify-between"><Skeleton className="h-3 w-28" /><Skeleton className="h-8 w-28" /></div>
        </div>
      ))}
    </div>
  )
}

function QueueEmpty({ onUpload }: { onUpload: () => void }) {
  return (
    <div className="flex min-h-80 flex-col items-center justify-center px-6 py-10 text-center">
      <span className="flex size-11 items-center justify-center rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]"><FileCheck2 className="size-5 text-[var(--text-muted)]" /></span>
      <h2 className="mt-4 text-base font-semibold">No documents in this view</h2>
      <p className="mt-1 max-w-sm text-sm leading-6 text-[var(--text-muted)]">Upload PDFs for organisation-wide intake, or clear the current queue filters.</p>
      <Button className="mt-4" onClick={onUpload}><Upload className="size-4" />Upload PDFs</Button>
    </div>
  )
}

function QueueError({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="m-4 rounded-[var(--radius-md)] border border-[var(--danger)] bg-[var(--danger-muted)] p-4">
      <div className="flex items-start gap-3">
        <CircleAlert className="mt-0.5 size-5 shrink-0 text-[var(--danger)]" />
        <div><h2 className="text-sm font-semibold">The queue could not be loaded</h2><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">Your filters are preserved. Retry the fixture to restore the sample queue.</p></div>
      </div>
      <Button variant="outline" size="sm" className="mt-4" onClick={onRetry}><RefreshCw className="size-4" />Retry queue</Button>
    </div>
  )
}

function QueueRow({ item, selected, onSelect }: { item: QueueItem; selected: boolean; onSelect: () => void }) {
  return (
    <article className={cn('border-b border-[var(--border-subtle)] transition-colors', selected ? 'bg-[var(--accent-muted)]' : 'bg-[var(--surface)] hover:bg-[var(--surface-hover)]')}>
      <button
        type="button"
        onClick={onSelect}
        aria-current={selected ? 'true' : undefined}
        className="block min-h-24 w-full px-4 py-3 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]"
      >
        <span className="flex items-start gap-3">
          <span className="min-w-0 flex-1">
            <span className="block break-words text-sm font-semibold leading-5 text-[var(--text-primary)]">{item.name}</span>
            <span className="mt-1 block truncate text-[11px] text-[var(--text-muted)]">{item.source}</span>
          </span>
          <StatusBadge status={item.status} />
        </span>
        <span className="mt-2 block truncate text-xs font-medium text-[var(--text-secondary)]">{item.destination}</span>
        <span className="mt-2 flex items-end gap-3">
          <span className="min-w-0 flex-1 text-xs leading-5 text-[var(--text-muted)]">{item.detail}</span>
          <span className="shrink-0 text-[11px] text-[var(--text-disabled)]">{item.age}</span>
        </span>
        <span className="mt-2 flex items-center gap-1 text-xs font-semibold text-[var(--primary)]">{item.action}<ChevronRight className="size-3.5" /></span>
      </button>
    </article>
  )
}

function QueueBody({
  state,
  items,
  selectedId,
  onSelect,
  onUpload,
  onRetry,
}: {
  state: PreviewState
  items: QueueItem[]
  selectedId: string
  onSelect: (item: QueueItem) => void
  onUpload: () => void
  onRetry: () => void
}) {
  if (state === 'loading') return <QueueLoading />
  if (state === 'empty') return <QueueEmpty onUpload={onUpload} />
  if (state === 'error') return <QueueError onRetry={onRetry} />
  return <>{items.map((item) => <QueueRow key={item.id} item={item} selected={selectedId === item.id} onSelect={() => onSelect(item)} />)}</>
}

function QueueFilters({ active, onChange }: { active: QueueFilter; onChange: (filter: QueueFilter) => void }) {
  return (
    <div className="grid grid-cols-4 border-b border-[var(--border)] bg-[var(--surface)] px-2" role="tablist" aria-label="Queue status groups">
      {filters.map((filter) => (
        <button
          key={filter}
          type="button"
          role="tab"
          aria-selected={active === filter}
          onClick={() => onChange(filter)}
          className={cn('min-h-11 border-b-2 px-1 text-[11px] font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]', active === filter ? 'border-[var(--primary)] text-[var(--text-primary)]' : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text-primary)]')}
        >
          {filter}
        </button>
      ))}
    </div>
  )
}

function PdfPlaceholder({ onQuote }: { onQuote: () => void }) {
  return (
    <div className="mx-auto flex w-full max-w-[760px] flex-col items-center gap-5 px-3 py-5 sm:px-6">
      {[1, 2].map((page) => (
        <article key={page} className="relative aspect-[0.707] w-full overflow-hidden rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] p-[7%] shadow-[var(--shadow-sm)]">
          <div className="absolute inset-x-0 top-0 border-b border-[var(--border-subtle)] bg-[var(--warning-muted)] px-3 py-1 text-center text-[10px] font-semibold text-[var(--warning)]">READABLE PAGE PLACEHOLDER · FIXTURE ONLY · NOT A PDF RENDER</div>
          <div className="mt-4 text-center">
            <p className="text-[9px] font-semibold uppercase tracking-[0.14em] text-[var(--text-muted)]">Illustrative tax authority</p>
            <h3 className="mt-2 text-sm font-semibold sm:text-base">FORM GST DRC-01A — FIXTURE NOTICE</h3>
            <p className="mt-1 font-mono text-[9px] text-[var(--text-muted)] sm:text-[11px]">Reference: DEMO/DRC01A/2026/0142</p>
          </div>
          <div className="mt-[8%] grid grid-cols-[32%_1fr] gap-x-4 gap-y-2 border-y border-[var(--border)] py-3 text-[8px] leading-4 sm:text-[11px] sm:leading-5">
            <span className="text-[var(--text-muted)]">Illustrative taxpayer</span><span className="font-medium">Apex Auto Components (fixture)</span>
            <span className="text-[var(--text-muted)]">Financial year</span><span className="font-mono">2023–24</span>
            <span className="text-[var(--text-muted)]">Matter code cited</span><span className="font-mono">MAT-2024-018</span>
          </div>
          <div className="mt-[7%] space-y-[5%] text-[8px] leading-4 text-[var(--text-secondary)] sm:text-[11px] sm:leading-5">
            <p><span className="mr-2 font-semibold text-[var(--text-primary)]">{page === 1 ? '1.' : '4.'}</span>This fictional passage exists only to demonstrate a readable continuous-page viewer. No legal assertion, real party, or uploaded file is represented here.</p>
            <button
              type="button"
              onClick={onQuote}
              className="block w-full rounded-[var(--radius-sm)] border border-[var(--primary)] bg-[var(--accent-muted)] p-2 text-left text-[var(--text-primary)] focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
            >
              <span className="mr-2 font-semibold">{page === 1 ? '2.' : '5.'}</span>
              {page === 1 ? 'The reconciliation explains the principal mismatch, subject to verification of the remaining illustrative invoice references.' : 'This second placeholder page proves that native scrolling is the primary navigation method; page controls remain supplementary.'}
              <span className="mt-1 flex items-center gap-1 text-[9px] font-semibold text-[var(--primary)] sm:text-[10px]"><Highlighter className="size-3" />Select this fixture passage for a note</span>
            </button>
            <p><span className="mr-2 font-semibold text-[var(--text-primary)]">{page === 1 ? '3.' : '6.'}</span>Extracted facts, source locations, and review state would be loaded from the immutable document version in production.</p>
          </div>
          <span className="absolute bottom-4 left-1/2 -translate-x-1/2 font-mono text-[9px] text-[var(--text-muted)]">Fixture page {page} of 14</span>
        </article>
      ))}
    </div>
  )
}

function ViewerPane({ onQuote }: { onQuote: () => void }) {
  const [zoom, setZoom] = useState(100)
  return (
    <section aria-label="Document page preview" className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden bg-[var(--bg-overlay)]">
      <div className="flex min-h-12 shrink-0 items-center gap-1 border-b border-[var(--border)] bg-[var(--surface)] px-2 sm:gap-2 sm:px-3">
        <Button variant="ghost" size="icon" aria-label="Previous page"><ChevronLeft className="size-4" /></Button>
        <label className="flex items-center gap-1 text-xs text-[var(--text-muted)]"><span className="sr-only sm:not-sr-only">Page</span><Input aria-label="Current page" value="1" readOnly className="h-8 w-10 px-2 text-center font-mono text-xs" /><span>/ 14</span></label>
        <Button variant="ghost" size="icon" aria-label="Next page"><ChevronRight className="size-4" /></Button>
        <span className="mx-1 h-5 w-px bg-[var(--border)]" />
        <Button variant="ghost" size="icon" aria-label="Zoom out" onClick={() => setZoom((value) => Math.max(75, value - 25))}><ZoomOut className="size-4" /></Button>
        <span className="min-w-9 text-center font-mono text-[11px] text-[var(--text-muted)]">{zoom}%</span>
        <Button variant="ghost" size="icon" aria-label="Zoom in" onClick={() => setZoom((value) => Math.min(150, value + 25))}><ZoomIn className="size-4" /></Button>
        <Button variant="ghost" size="sm" className="hidden lg:inline-flex">Fit width</Button>
        <Button variant="ghost" size="icon" aria-label="Rotate page"><RotateCw className="size-4" /></Button>
        <Button variant="ghost" size="sm" className="ml-auto hidden sm:inline-flex"><Search className="size-4" />Search document</Button>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain" style={{ scrollbarGutter: 'stable' }}>
        <PdfPlaceholder onQuote={onQuote} />
      </div>
    </section>
  )
}

function EvidenceLine({ children, warning = false }: { children: React.ReactNode; warning?: boolean }) {
  return (
    <div className="flex items-start gap-2 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-2.5 text-xs leading-5">
      {warning ? <AlertTriangle className="mt-0.5 size-4 shrink-0 text-[var(--warning)]" /> : <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-[var(--success)]" />}
      <span>{children}</span>
    </div>
  )
}

function PlacementInspector({ role, onPreview }: { role: RolePreview; onPreview: (message: string) => void }) {
  const readOnly = role === 'Viewer'
  const [classification, setClassification] = useState<'Proceeding' | 'Supporting'>('Proceeding')
  return (
    <div className="space-y-5 p-4">
      {readOnly && <div className="flex items-start gap-2 rounded-[var(--radius-sm)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3 text-xs leading-5"><LockKeyhole className="mt-0.5 size-4 shrink-0" /><span><strong>Viewer preview.</strong> Evidence remains readable; placement and recovery actions are unavailable.</span></div>}
      <section>
        <div className="flex items-center gap-2"><h3 className="text-sm font-semibold">Recommended matter</h3><Badge variant="warning">Suggestion only</Badge></div>
        <div className="mt-3 rounded-[var(--radius-md)] border border-[var(--border-strong)] p-3">
          <div className="font-semibold">Apex Auto Components</div>
          <div className="mt-1 font-mono text-xs text-[var(--text-muted)]">MAT-2024-018 · FY 2023–24</div>
          <div className="mt-3 space-y-2">
            <EvidenceLine>Exact matter code <span className="font-mono">MAT-2024-018</span> appears on fixture page 1</EvidenceLine>
            <EvidenceLine>Verified GSTIN and financial year agree with this matter</EvidenceLine>
          </div>
        </div>
      </section>
      <section>
        <label htmlFor="matter-search" className="text-xs font-medium text-[var(--text-secondary)]">Choose another accessible matter</label>
        <div className="relative mt-1.5"><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" /><Input id="matter-search" placeholder="Search client, matter, or code" className="pl-9" disabled={readOnly} /></div>
      </section>
      <section>
        <h3 className="text-xs font-medium text-[var(--text-secondary)]">Classification</h3>
        <div className="mt-2 grid grid-cols-2 gap-2" role="group" aria-label="Document classification">
          {(['Proceeding', 'Supporting'] as const).map((option) => <Button key={option} variant={classification === option ? 'secondary' : 'outline'} disabled={readOnly} aria-pressed={classification === option} onClick={() => { setClassification(option); onPreview(`${option} classification selected for this fixture.`) }}>{option}</Button>)}
        </div>
      </section>
      <div className="border-t border-[var(--border)] pt-4">
        <Button className="w-full" disabled={readOnly} onClick={() => onPreview('Assignment preview complete. No document or matter was changed.')}><FileCheck2 className="size-4" />Preview assignment</Button>
        <Button variant="link" className="mt-3 w-full" disabled={readOnly} onClick={() => onPreview('Client and matter proposal preview opened. No record was created.')}><Plus className="size-4" />Preview client and matter proposal</Button>
      </div>
    </div>
  )
}

function AtAGlanceInspector() {
  return (
    <div className="space-y-5 p-4">
      <section>
        <h3 className="text-sm font-semibold">At a glance</h3>
        <dl className="mt-3 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)]">
          {[
            ['Type', 'DRC-01A notice · provisional'],
            ['Reference', 'DEMO/DRC01A/2026/0142'],
            ['Issue date', '27 Aug 2026'],
            ['Readability', 'Native text · 2 OCR pages'],
          ].map(([label, value]) => <div key={label} className="grid grid-cols-[92px_1fr] gap-3 border-b border-[var(--border-subtle)] px-3 py-2.5 last:border-b-0"><dt className="text-xs text-[var(--text-muted)]">{label}</dt><dd className="break-words text-xs font-medium">{value}</dd></div>)}
        </dl>
      </section>
      <section>
        <div className="flex items-center justify-between"><h3 className="text-sm font-semibold">Deadlines</h3><Badge variant="warning">Verify</Badge></div>
        <div className="mt-2 rounded-[var(--radius-sm)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3"><div className="text-sm font-semibold">Reply due 18 Sep 2026</div><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">Extracted from fixture page 4 · not yet verified</p><Button variant="link" className="mt-2">Open source page</Button></div>
      </section>
      <section>
        <h3 className="text-sm font-semibold">Financial facts</h3>
        <div className="mt-2 flex items-center justify-between rounded-[var(--radius-sm)] border border-[var(--border-subtle)] p-3"><span className="text-xs text-[var(--text-muted)]">Proposed tax</span><span className="font-mono text-sm font-semibold">₹14,20,000</span></div>
      </section>
      <section>
        <h3 className="text-sm font-semibold">Processing</h3>
        <div className="mt-2 space-y-2"><EvidenceLine>PDF validated and native text available</EvidenceLine><EvidenceLine warning>OCR quality is limited on fixture pages 7–8</EvidenceLine></div>
      </section>
    </div>
  )
}

function NotesInspector({ quoteOpen, onQuote, onPreview }: { quoteOpen: boolean; onQuote: () => void; onPreview: (message: string) => void }) {
  return (
    <div className="space-y-4 p-4">
      <section>
        <h3 className="text-sm font-semibold">Document notes</h3>
        <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Quotes retain the immutable version, page, text method, and normalized region.</p>
      </section>
      {quoteOpen ? (
        <div className="rounded-[var(--radius-md)] border border-[var(--primary)] bg-[var(--accent-muted)] p-3">
          <div className="flex items-center gap-2 text-xs font-semibold text-[var(--primary)]"><Highlighter className="size-4" />Quotation context · fixture page 1</div>
          <blockquote className="mt-3 border-l-2 border-[var(--primary)] pl-3 text-sm leading-6">The reconciliation explains the principal mismatch, subject to verification of the remaining illustrative invoice references.</blockquote>
          <div className="mt-3 flex flex-wrap gap-2"><Badge variant="outline">Native text</Badge><Badge variant="outline">Version fixture-v1</Badge></div>
          <Button className="mt-4 w-full" onClick={() => onPreview('Quoted-note preview complete. No note was created.')}><MessageSquareText className="size-4" />Preview note with quote</Button>
        </div>
      ) : (
        <button type="button" onClick={onQuote} className="w-full rounded-[var(--radius-md)] border border-dashed border-[var(--border-strong)] p-5 text-center hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">
          <Highlighter className="mx-auto size-5 text-[var(--text-muted)]" /><span className="mt-2 block text-sm font-semibold">Select a fixture passage</span><span className="mt-1 block text-xs text-[var(--text-muted)]">The viewer will preserve page and region context.</span>
        </button>
      )}
      <div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] p-3"><div className="text-xs font-semibold">Meera Shah · 28 Aug, 10:17</div><p className="mt-2 text-xs leading-5 text-[var(--text-secondary)]">Please confirm the remaining invoice references before placement.</p></div>
    </div>
  )
}

function InspectorPane({ role, mode, quoteOpen, onModeChange, onQuote, onPreview }: { role: RolePreview; mode: WorkbenchMode; quoteOpen: boolean; onModeChange: (mode: WorkbenchMode) => void; onQuote: () => void; onPreview: (message: string) => void }) {
  const tabs: Array<{ id: WorkbenchMode; label: string }> = [
    { id: 'placement', label: 'Placement' },
    { id: 'details', label: 'Details' },
    { id: 'notes', label: 'Notes' },
  ]
  return (
    <aside aria-label="Document inspector" className="flex h-full min-h-0 min-w-0 flex-col overflow-hidden border-l border-[var(--border)] bg-[var(--surface)]">
      <div className="flex min-h-12 shrink-0 border-b border-[var(--border)] px-2" role="tablist" aria-label="Inspector sections">
        {tabs.map((tab) => <button key={tab.id} id={`inspector-tab-${tab.id}`} type="button" role="tab" aria-selected={mode === tab.id} aria-controls={`inspector-panel-${tab.id}`} tabIndex={mode === tab.id ? 0 : -1} onClick={() => onModeChange(tab.id)} className={cn('min-h-11 flex-1 border-b-2 px-2 text-xs font-medium', mode === tab.id ? 'border-[var(--primary)] text-[var(--text-primary)]' : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text-primary)]')}>{tab.label}</button>)}
      </div>
      <div role="tabpanel" id={`inspector-panel-${mode}`} aria-labelledby={`inspector-tab-${mode}`} tabIndex={0} className="min-h-0 flex-1 overflow-y-auto overscroll-contain" style={{ scrollbarGutter: 'stable' }}>
        {mode === 'placement' ? <PlacementInspector role={role} onPreview={onPreview} /> : mode === 'notes' ? <NotesInspector quoteOpen={quoteOpen} onQuote={onQuote} onPreview={onPreview} /> : <AtAGlanceInspector />}
        <div className="mx-4 mb-5 border-t border-[var(--border)] pt-4"><Button variant="destructive" size="sm" disabled={role === 'Viewer'} onClick={() => onPreview('Discard preview complete. The fixture upload remains in the queue.')}>Preview discard</Button><p className="mt-2 text-[11px] leading-4 text-[var(--text-muted)]">Preview only. No upload is removed and no production command runs.</p></div>
      </div>
    </aside>
  )
}

function WorkbenchHeader({ item, role, inspectorTrigger, onPreview }: { item: QueueItem; role: RolePreview; inspectorTrigger: React.ReactNode; onPreview: (message: string) => void }) {
  return (
    <header className="flex min-h-[70px] shrink-0 items-center gap-3 border-b border-[var(--border)] bg-[var(--surface)] px-3 sm:px-4">
      <span className="hidden size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] sm:flex"><FileText className="size-4 text-[var(--text-secondary)]" /></span>
      <div className="min-w-0 flex-1"><div className="flex min-w-0 items-center gap-2"><h2 className="truncate text-sm font-semibold">{item.name}</h2><StatusBadge status={item.status} /></div><p className="mt-1 truncate text-[11px] text-[var(--text-muted)]">Intake fixture · {item.pages || 'Unknown'} pages · Version fixture-v1</p></div>
      {role === 'Viewer' && <Badge variant="warning" className="hidden sm:inline-flex"><LockKeyhole className="size-3" />Read only</Badge>}
      {inspectorTrigger}
      <DropdownMenu>
        <DropdownMenuTrigger asChild><Button variant="ghost" size="icon" aria-label="More document actions"><MoreHorizontal className="size-4" /></Button></DropdownMenuTrigger>
        <DropdownMenuContent align="end"><DropdownMenuLabel>Preview-only actions</DropdownMenuLabel><DropdownMenuSeparator /><DropdownMenuItem onSelect={() => onPreview('Download preview complete. No file was downloaded.')}><Download className="size-4" />Preview download</DropdownMenuItem><DropdownMenuItem disabled={role === 'Viewer'} onSelect={() => onPreview('Move or copy preview complete. No document was changed.')}><Copy className="size-4" />Preview move or copy</DropdownMenuItem></DropdownMenuContent>
      </DropdownMenu>
    </header>
  )
}

function DesktopWorkbench({ item, role, quoteOpen, onQuote, onPreview }: { item: QueueItem; role: RolePreview; quoteOpen: boolean; onQuote: () => void; onPreview: (message: string) => void }) {
  const [inspectorMode, setInspectorMode] = useState<WorkbenchMode>('placement')
  const [drawerOpen, setDrawerOpen] = useState(false)
  return (
    <Dialog open={drawerOpen} onOpenChange={setDrawerOpen}>
      <section aria-label="Document Workbench fixture" className="relative flex min-h-0 min-w-0 flex-col overflow-hidden bg-[var(--surface)]">
        <WorkbenchHeader item={item} role={role} onPreview={onPreview} inspectorTrigger={<DialogTrigger asChild><Button variant="outline" size="sm" className="xl:hidden"><PanelRightOpen className="size-4" />Details</Button></DialogTrigger>} />
        <div className="grid min-h-0 flex-1 grid-cols-1 xl:grid-cols-[minmax(0,1.7fr)_minmax(320px,1fr)]">
          <ViewerPane onQuote={() => { onQuote(); setInspectorMode('notes'); setDrawerOpen(true) }} />
          <div className="hidden h-full min-h-0 xl:block"><InspectorPane role={role} mode={inspectorMode} quoteOpen={quoteOpen} onModeChange={setInspectorMode} onQuote={onQuote} onPreview={onPreview} /></div>
        </div>
      </section>
      <DialogContent showClose={false} aria-describedby="document-details-drawer-description" className="left-auto right-0 top-0 flex h-dvh w-[min(430px,calc(100vw-2rem))] max-w-none translate-x-0 translate-y-0 flex-col overflow-hidden rounded-none border-y-0 border-r-0 p-0 sm:max-w-[430px] xl:hidden">
        <div className="flex min-h-14 shrink-0 items-center gap-3 border-b border-[var(--border)] px-3"><div><DialogTitle className="text-sm">Document details</DialogTitle><DialogDescription id="document-details-drawer-description" className="text-xs">Fixture inspector for the selected intake item.</DialogDescription></div><DialogClose asChild><Button variant="ghost" size="icon" className="ml-auto" aria-label="Close document details"><X className="size-4" /></Button></DialogClose></div>
        <div className="min-h-0 flex-1"><InspectorPane role={role} mode={inspectorMode} quoteOpen={quoteOpen} onModeChange={setInspectorMode} onQuote={onQuote} onPreview={onPreview} /></div>
      </DialogContent>
    </Dialog>
  )
}

function MobileWorkbench({ item, role, onBack, quoteOpen, onQuote, onPreview }: { item: QueueItem; role: RolePreview; onBack: () => void; quoteOpen: boolean; onQuote: () => void; onPreview: (message: string) => void }) {
  const [mode, setMode] = useState<WorkbenchMode>('document')
  return (
    <section className="flex h-full min-h-0 flex-col overflow-hidden bg-[var(--surface)]">
      <header className="flex min-h-14 shrink-0 items-center gap-2 border-b border-[var(--border)] px-2"><Button variant="ghost" size="icon" onClick={onBack} aria-label="Back to document queue"><ArrowLeft className="size-5" /></Button><div className="min-w-0 flex-1"><h2 className="truncate text-sm font-semibold">{item.name}</h2><p className="truncate text-[11px] text-[var(--text-muted)]">{item.status} · Intake fixture</p></div><StatusBadge status={item.status} /></header>
      <nav className="grid shrink-0 grid-cols-4 border-b border-[var(--border)] bg-[var(--surface)]" aria-label="Workbench modes">
        {[
          { id: 'document' as const, label: 'Document', icon: BookOpen },
          { id: 'details' as const, label: 'Details', icon: Info },
          { id: 'notes' as const, label: 'Notes', icon: MessageSquareText },
          { id: 'placement' as const, label: 'Placement', icon: FileCheck2 },
        ].map(({ id, label, icon: Icon }) => <button key={id} type="button" onClick={() => setMode(id)} aria-current={mode === id ? 'page' : undefined} className={cn('flex min-h-14 flex-col items-center justify-center gap-1 border-b-2 text-[11px] font-medium', mode === id ? 'border-[var(--primary)] text-[var(--primary)]' : 'border-transparent text-[var(--text-muted)]')}><Icon className="size-4" />{label}</button>)}
      </nav>
      <div className="flex min-h-0 flex-1 overflow-hidden">
        {mode === 'document' ? <ViewerPane onQuote={() => { onQuote(); setMode('notes') }} /> : <div className="h-full min-w-0 flex-1 overflow-y-auto">{mode === 'placement' ? <PlacementInspector role={role} onPreview={onPreview} /> : mode === 'notes' ? <NotesInspector quoteOpen={quoteOpen} onQuote={onQuote} onPreview={onPreview} /> : <AtAGlanceInspector />}</div>}
      </div>
      {mode === 'placement' && <div className="shrink-0 border-t border-[var(--border)] bg-[var(--surface)] p-2"><Button className="h-11 w-full" disabled={role === 'Viewer'} onClick={() => onPreview('Assignment preview complete. No document or matter was changed.')}>Preview assignment</Button></div>}
    </section>
  )
}

function FiltersDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent showClose={false}>
        <DialogHeader className="relative pr-10"><DialogTitle>Filter Document Hub</DialogTitle><DialogDescription>Fixture controls show how destination, uploader, classification, and state filters can move into a compact overlay.</DialogDescription><DialogClose asChild><Button variant="ghost" size="icon" className="absolute -right-3 -top-3" aria-label="Close filters"><X className="size-4" /></Button></DialogClose></DialogHeader>
        <div className="space-y-4">
          <label className="block"><span className="mb-1.5 block text-xs font-medium">Destination context</span><Input value="All accessible matters" readOnly /></label>
          <fieldset><legend className="mb-2 text-xs font-medium">State</legend><div className="grid grid-cols-2 gap-2">{['Needs placement', 'Processing', 'Review', 'Failed'].map((label, index) => <label key={label} className="flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] px-3 text-sm"><input type="checkbox" defaultChecked={index < 2} className="accent-[var(--primary)]" />{label}</label>)}</div></fieldset>
        </div>
        <DialogFooter><Button variant="outline" onClick={() => onOpenChange(false)}>Clear filters</Button><Button onClick={() => onOpenChange(false)}>Apply filters</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

export function DocumentHubWorkbenchConcept() {
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [previewState, setPreviewState] = useState<PreviewState>('default')
  const [role, setRole] = useState<RolePreview>('Associate')
  const [activeFilter, setActiveFilter] = useState<QueueFilter>('Needs action')
  const [selectedId, setSelectedId] = useState('placement')
  const [mobileDetail, setMobileDetail] = useState(false)
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [quoteOpen, setQuoteOpen] = useState(false)
  const [trayOpen, setTrayOpen] = useState(false)
  const [announcement, setAnnouncement] = useState('')

  const allItems = useMemo(() => previewState === 'long' ? [longContentItem, ...queueItems] : queueItems, [previewState])
  const items = useMemo(() => allItems.filter((item) => matchesQueueFilter(item, activeFilter)), [activeFilter, allItems])
  const selected = items.find((item) => item.id === selectedId) ?? items[0] ?? allItems[0]

  const showUploadFixture = () => {
    setPreviewState('upload')
    setTrayOpen(true)
    setAnnouncement('Upload tray fixture opened. No file is uploaded or stored.')
  }

  const openNativePicker = () => fileInputRef.current?.click()

  const changePreview = (state: PreviewState) => {
    setPreviewState(state)
    setTrayOpen(state === 'upload')
    if (state === 'long') setSelectedId('long')
  }

  const selectItem = (item: QueueItem) => {
    setSelectedId(item.id)
    setMobileDetail(true)
    setQuoteOpen(false)
  }

  return (
    <div className="relative flex h-dvh min-w-0 flex-col overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]">
      <input ref={fileInputRef} type="file" accept="application/pdf,.pdf" multiple hidden tabIndex={-1} aria-hidden="true" onChange={showUploadFixture} />
      <header className="shrink-0 border-b border-[var(--border)] bg-[var(--surface)]">
        <div className="flex min-h-14 items-center gap-2 px-3 sm:px-4">
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2"><h1 className="truncate text-lg font-semibold sm:text-xl">Document Hub</h1><Badge variant="outline" className="hidden sm:inline-flex">Fixture concept</Badge></div>
            <p className="truncate text-[11px] text-[var(--text-muted)]">{items.length} items in {activeFilter.toLocaleLowerCase()} · updated in place · no production data</p>
          </div>
          <div className="hidden items-center gap-2 lg:flex"><RoleMenu role={role} onRoleChange={setRole} /><FixtureMenu state={previewState} onStateChange={changePreview} /></div>
          <ThemeToggle />
          <Button onClick={openNativePicker}><Upload className="size-4" /><span className="hidden sm:inline">Upload PDFs</span><span className="sm:hidden">Upload</span></Button>
        </div>
        <div className="flex min-h-12 items-center gap-2 border-t border-[var(--border-subtle)] px-3 sm:px-4 lg:hidden">
          <RoleMenu role={role} onRoleChange={setRole} /><FixtureMenu state={previewState} onStateChange={changePreview} />
        </div>
      </header>

      <main className="relative min-h-0 flex-1 overflow-hidden">
        <div className="hidden h-full min-h-0 grid-cols-[340px_minmax(0,1fr)] md:grid">
          <section aria-label="Document queue" className="flex min-h-0 flex-col overflow-hidden border-r border-[var(--border)] bg-[var(--surface)]">
            <div className="flex min-h-12 shrink-0 items-center gap-2 border-b border-[var(--border)] px-3"><div className="relative min-w-0 flex-1"><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" /><Input aria-label="Search document queue" placeholder="Search queue" className="pl-9" /></div><Button variant="outline" size="icon" onClick={() => setFiltersOpen(true)} aria-label="Filter queue"><Filter className="size-4" /></Button></div>
            <QueueFilters active={activeFilter} onChange={setActiveFilter} />
            <div
              className="min-h-0 flex-1 overflow-y-auto overscroll-contain"
              style={{ scrollbarGutter: 'stable' }}
              onDragOver={(event) => event.preventDefault()}
              onDrop={(event) => { event.preventDefault(); showUploadFixture() }}
            >
              <QueueBody state={previewState} items={items} selectedId={selected.id} onSelect={selectItem} onUpload={openNativePicker} onRetry={() => changePreview('default')} />
            </div>
          </section>
          <DesktopWorkbench item={selected} role={role} quoteOpen={quoteOpen} onQuote={() => setQuoteOpen(true)} onPreview={setAnnouncement} />
        </div>

        <div className="h-full min-h-0 md:hidden">
          {mobileDetail ? <MobileWorkbench item={selected} role={role} onBack={() => setMobileDetail(false)} quoteOpen={quoteOpen} onQuote={() => setQuoteOpen(true)} onPreview={setAnnouncement} /> : (
            <section aria-label="Document queue" className="flex h-full min-h-0 flex-col overflow-hidden bg-[var(--surface)]">
              <div className="flex min-h-14 shrink-0 items-center gap-2 border-b border-[var(--border)] px-3"><div className="relative min-w-0 flex-1"><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" /><Input aria-label="Search document queue" placeholder="Search queue" className="pl-9" /></div><Button variant="outline" size="icon" onClick={() => setFiltersOpen(true)} aria-label="Filter queue"><ListFilter className="size-4" /></Button></div>
              <QueueFilters active={activeFilter} onChange={setActiveFilter} />
              <div className="min-h-0 flex-1 overflow-y-auto"><QueueBody state={previewState} items={items} selectedId={selected.id} onSelect={selectItem} onUpload={openNativePicker} onRetry={() => changePreview('default')} /></div>
            </section>
          )}
        </div>
      </main>

      {trayOpen && <UploadTray onClose={() => setTrayOpen(false)} />}
      <FiltersDialog open={filtersOpen} onOpenChange={setFiltersOpen} />
      <div aria-live="polite" aria-atomic="true" className={cn('pointer-events-none absolute bottom-3 left-1/2 z-[60] w-[min(460px,calc(100vw-2rem))] -translate-x-1/2 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-center text-xs shadow-[var(--shadow-md)] transition-opacity', announcement ? 'opacity-100' : 'opacity-0')}>{announcement}</div>
    </div>
  )
}
