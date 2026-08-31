'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import { useTheme } from 'next-themes'
import {
  AlertTriangle,
  ArchiveX,
  ArrowLeft,
  Check,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  CircleAlert,
  Clock3,
  DatabaseZap,
  FileCheck2,
  FileText,
  Fingerprint,
  FolderOpen,
  Gavel,
  Info,
  Link2,
  Loader2,
  LockKeyhole,
  Moon,
  Network,
  NotebookText,
  ReceiptText,
  RefreshCw,
  ShieldAlert,
  ShieldCheck,
  Sun,
  Trash2,
  Users,
  WalletCards,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
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
import { Label } from '@/components/ui/label'
import { Skeleton } from '@/components/ui/skeleton'
import { cn } from '@/lib/utils'

type PreviewRole = 'owner-admin' | 'associate' | 'viewer'
type PreviewState =
  | 'impact-ready'
  | 'recent-auth-required'
  | 'hold-blocked'
  | 'impact-pending'
  | 'purging'
  | 'purge-failed'
  | 'purged'
  | 'loading'
  | 'empty'
  | 'error'
  | 'long-content'
type ReviewStep = 'impact' | 'confirmation'

const confirmationCode = 'KAV-COMP-1042'

const roleLabels: Record<PreviewRole, string> = {
  'owner-admin': 'Owner / Admin',
  associate: 'Associate',
  viewer: 'Viewer',
}

const stateLabels: Record<PreviewState, string> = {
  'impact-ready': 'Impact ready',
  'recent-auth-required': 'Recent auth required',
  'hold-blocked': 'Hold / blocker',
  'impact-pending': 'Impact pending',
  purging: 'Purge in progress',
  'purge-failed': 'Purge failed',
  purged: 'Already purged',
  loading: 'Loading',
  empty: 'No selection',
  error: 'Load error',
  'long-content': 'Long content',
}

const consequenceGroups = [
  { icon: NotebookText, label: 'Notes & brief history', value: '48 notes · 112 history entries', detail: 'Permanent deletion removes note bodies, brief versions, and their retained revision history.' },
  { icon: FileCheck2, label: 'Citations & extracted facts', value: '19 citations · 286 facts', detail: 'Citations, quotations, provenance links, embeddings, and extracted facts cannot be reconstructed from the tombstone.' },
  { icon: Clock3, label: 'Deadlines & reminders', value: '7 deadlines · 4 reminders', detail: 'Suspended schedules and reminder deliveries are removed. No missed reminder is sent.' },
  { icon: WalletCards, label: 'Financials', value: '12 entries · ₹1,84,500 tracked', detail: 'Matter-level fee and expense records owned only by this group are permanently deleted.' },
  { icon: Link2, label: 'Relationships', value: '9 links · 3 external endpoints retained', detail: 'Links are removed. Records outside this group remain, without exposing content from the deleted endpoint.' },
  { icon: Network, label: 'Jobs & projections', value: '3 jobs · search and review projections', detail: 'Jobs are disabled before derived data, search, notifications, tasks, and review projections are removed.' },
]

const includedItems = [
  { icon: FolderOpen, type: 'Matter', name: 'FY 2024–25 ITC reconciliation', meta: '18 documents' },
  { icon: FolderOpen, type: 'Matter', name: 'Classification advisory', meta: '10 documents' },
  { icon: FileText, type: 'Document', name: 'Supplier confirmations — consolidated ledger and annexures for Q4 FY 2024–25.pdf', meta: 'Inherited child · no separate action' },
]

function PreviewMenu({
  role,
  state,
  onRoleChange,
  onStateChange,
  onAppearanceChange,
  onShowBoundary,
}: {
  role: PreviewRole
  state: PreviewState
  onRoleChange: (role: PreviewRole) => void
  onStateChange: (state: PreviewState) => void
  onAppearanceChange: (appearance: 'light' | 'dark') => void
  onShowBoundary: () => void
}) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm">
          Preview
          <ChevronDown className="size-3.5" aria-hidden="true" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="max-h-[min(34rem,calc(100vh-2rem))] w-72 overflow-y-auto">
        <DropdownMenuLabel>Access preview</DropdownMenuLabel>
        <DropdownMenuRadioGroup value={role} onValueChange={(value) => onRoleChange(value as PreviewRole)}>
          {(['owner-admin', 'associate', 'viewer'] as PreviewRole[]).map((option) => (
            <DropdownMenuRadioItem key={option} value={option}>{roleLabels[option]}</DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <DropdownMenuLabel>Impact and confirmation</DropdownMenuLabel>
        <DropdownMenuRadioGroup value={state} onValueChange={(value) => onStateChange(value as PreviewState)}>
          {(['impact-ready', 'recent-auth-required', 'hold-blocked', 'impact-pending', 'long-content'] as PreviewState[]).map((option) => (
            <DropdownMenuRadioItem key={option} value={option}>{stateLabels[option]}</DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <DropdownMenuLabel>Execution and page states</DropdownMenuLabel>
        <DropdownMenuRadioGroup value={state} onValueChange={(value) => onStateChange(value as PreviewState)}>
          {(['purging', 'purge-failed', 'purged', 'loading', 'empty', 'error'] as PreviewState[]).map((option) => (
            <DropdownMenuRadioItem key={option} value={option}>{stateLabels[option]}</DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <DropdownMenuLabel>Appearance preview</DropdownMenuLabel>
        <DropdownMenuItem onSelect={() => onAppearanceChange('light')}><Sun className="size-4" aria-hidden="true" />Preview light</DropdownMenuItem>
        <DropdownMenuItem onSelect={() => onAppearanceChange('dark')}><Moon className="size-4" aria-hidden="true" />Preview dark</DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem onSelect={onShowBoundary}><Info className="size-4" aria-hidden="true" />About this concept</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function RootIdentity({ longContent = false }: { longContent?: boolean }) {
  return (
    <section aria-labelledby="root-identity" className="border-b border-[var(--border-subtle)] p-4 sm:p-5">
      <div className="flex items-start gap-3">
        <span className="flex size-10 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--danger-muted)] text-[var(--danger)]">
          <Users className="size-5" aria-hidden="true" />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <p className="text-xs font-medium text-[var(--text-muted)]">Client root · Trash group OP-418</p>
            <Badge variant="danger">Direct root</Badge>
          </div>
          <h1 id="root-identity" className="mt-1 break-words text-lg font-semibold leading-7">
            {longContent ? 'Kaveri Components Private Limited, Consolidated Industrial Systems, Indirect Tax Appeals and Multi-State Record Preservation Division' : 'Kaveri Components Private Limited'}
          </h1>
          <p className="mt-1 font-mono text-xs text-[var(--text-muted)]">Exact confirmation code: {confirmationCode}</p>
        </div>
      </div>
      <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-3 text-xs sm:grid-cols-4">
        <div><dt className="text-[var(--text-muted)]">Deleted by</dt><dd className="mt-1 font-medium">Rishikesh Joshi</dd></div>
        <div><dt className="text-[var(--text-muted)]">Deleted on</dt><dd className="mt-1 font-mono">30 Aug 2026 · 10:32</dd></div>
        <div><dt className="text-[var(--text-muted)]">Scheduled deletion</dt><dd className="mt-1 font-mono">28 Nov 2026 · 10:32</dd></div>
        <div><dt className="text-[var(--text-muted)]">Retention snapshot</dt><dd className="mt-1">90 days · policy v7</dd></div>
      </dl>
    </section>
  )
}

function ImpactSummary({ blocked = false }: { blocked?: boolean }) {
  return (
    <section aria-labelledby="impact-summary" className="border-b border-[var(--border-subtle)] p-4 sm:p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 id="impact-summary" className="text-section-heading">Calculated impact</h2>
          <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Read-only snapshot calculated for the entire root operation. Nothing has been deleted permanently.</p>
        </div>
        <Badge variant={blocked ? 'warning' : 'success'} fixedWidth="xl">{blocked ? '1 active hold' : 'Impact complete'}</Badge>
      </div>
      <div className="mt-4 grid grid-cols-2 gap-px overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--border-subtle)] sm:grid-cols-4">
        {[
          ['Client roots', '1'],
          ['Matters', '4'],
          ['Documents', '28'],
          ['Dependent records', '499'],
        ].map(([label, value]) => (
          <div key={label} className="bg-[var(--surface)] p-3"><div className="font-mono text-lg font-semibold">{value}</div><div className="mt-0.5 text-xs text-[var(--text-muted)]">{label}</div></div>
        ))}
      </div>
      <div className="mt-3 grid gap-3 sm:grid-cols-2">
        <div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3">
          <div className="flex items-center gap-2 text-xs font-semibold"><ArchiveX className="size-4 text-[var(--danger)]" aria-hidden="true" />Unique storage eligible for deletion</div>
          <div className="mt-2 font-mono text-lg font-semibold">44.2 MB</div>
          <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Likely to be freed only after every purge stage is verified.</p>
        </div>
        <div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3">
          <div className="flex items-center gap-2 text-xs font-semibold"><ShieldCheck className="size-4 text-[var(--success)]" aria-hidden="true" />Shared assets retained safely</div>
          <div className="mt-2 font-mono text-lg font-semibold">4.4 MB</div>
          <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">3 PDFs remain because active records, Intake, or exports still reference them.</p>
        </div>
      </div>
    </section>
  )
}

function Consequences() {
  return (
    <section aria-labelledby="consequences" className="border-b border-[var(--border-subtle)] p-4 sm:p-5">
      <h2 id="consequences" className="text-section-heading">What permanent deletion removes</h2>
      <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">The whole group is purged in dependency order. Shared assets and mandatory content-free receipts are the only stated exceptions.</p>
      <div className="mt-4 grid gap-px overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--border-subtle)] sm:grid-cols-2">
        {consequenceGroups.map(({ icon: Icon, label, value, detail }) => (
          <div key={label} className="bg-[var(--surface)] p-3">
            <div className="flex items-start gap-2"><Icon className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" /><div className="min-w-0"><h3 className="text-xs font-semibold">{label}</h3><p className="mt-0.5 text-xs text-[var(--text-secondary)]">{value}</p><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">{detail}</p></div></div>
          </div>
        ))}
      </div>
    </section>
  )
}

function BlockerStatus({ blocked }: { blocked: boolean }) {
  return (
    <section aria-labelledby="safety-checks" className="border-b border-[var(--border-subtle)] p-4 sm:p-5">
      <h2 id="safety-checks" className="text-section-heading">Holds, exports, and safety checks</h2>
      <div className="mt-3 space-y-2">
        <div className={cn('flex items-start gap-3 rounded-[var(--radius-sm)] border p-3', blocked ? 'border-[var(--warning)] bg-[var(--warning-muted)]' : 'border-[var(--border-subtle)] bg-[var(--bg)]')}>
          {blocked ? <ShieldAlert className="mt-0.5 size-4 shrink-0 text-[var(--warning)]" aria-hidden="true" /> : <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-[var(--success)]" aria-hidden="true" />}
          <div className="min-w-0"><h3 className="text-xs font-semibold">{blocked ? 'Legal hold blocks the entire group' : 'No legal hold found'}</h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">{blocked ? 'Hold GST-AUDIT-77 covers one included document. Do not remove or work around it. Ask the hold owner to review the authority and release it only through the Holds workflow.' : 'Every included resource was checked. A new hold before execution will stop the purge safely.'}</p></div>
        </div>
        <div className="flex items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3">
          <FileCheck2 className="mt-0.5 size-4 shrink-0 text-[var(--success)]" aria-hidden="true" />
          <div><h3 className="text-xs font-semibold">No export or backup job blocks deletion</h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">If an export starts before execution, finish or cancel it safely and calculate impact again.</p></div>
        </div>
      </div>
    </section>
  )
}

function IncludedHierarchy() {
  return (
    <section aria-labelledby="included-items" className="p-4 sm:p-5">
      <div className="flex flex-wrap items-center justify-between gap-2"><h2 id="included-items" className="text-section-heading">Included hierarchy</h2><span className="text-xs text-[var(--text-muted)]">Showing 3 of 32 included items</span></div>
      <div className="mt-3 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)]">
        {includedItems.map(({ icon: Icon, type, name, meta }, index) => (
          <div key={name} className={cn('flex items-start gap-3 bg-[var(--surface)] p-3', index > 0 && 'border-t border-[var(--border-subtle)]')}>
            <Icon className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" />
            <div className="min-w-0 flex-1"><div className="flex flex-wrap items-center gap-2"><h3 className="break-words text-xs font-semibold">{name}</h3><Badge variant="muted">Inherited</Badge></div><p className="mt-1 text-xs text-[var(--text-muted)]">{type} · {meta}</p></div>
          </div>
        ))}
      </div>
      <div className="mt-3 flex items-start gap-2 text-xs leading-5 text-[var(--text-muted)]"><Info className="mt-0.5 size-4 shrink-0" aria-hidden="true" /><span>Inherited children cannot be permanently deleted separately. This operation always targets the direct client root and all memberships owned by Trash group OP-418.</span></div>
    </section>
  )
}

function ImpactPane({ state }: { state: PreviewState }) {
  if (state === 'purged') {
    return (
      <section aria-label="Purged operation receipt" className="min-w-0 flex-1 bg-[var(--surface)] p-4 sm:p-5">
        <div className="mx-auto max-w-2xl rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--bg)] p-4">
          <div className="flex items-start gap-3"><ReceiptText className="mt-0.5 size-5 shrink-0 text-[var(--text-muted)]" aria-hidden="true" /><div><h1 className="text-section-heading">Deleted content is no longer available</h1><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Names, filenames, codes, legal content, dependency details, and storage paths were removed from this view. The receipt cannot reconstruct the deleted records.</p></div></div>
          <dl className="mt-4 grid grid-cols-2 gap-3 border-t border-[var(--border-subtle)] pt-4 text-xs"><div><dt className="text-[var(--text-muted)]">Operation</dt><dd className="mt-1 font-mono">OP-418</dd></div><div><dt className="text-[var(--text-muted)]">Former opaque ID</dt><dd className="mt-1 font-mono">client_8a4f…1c72</dd></div><div><dt className="text-[var(--text-muted)]">Resource type</dt><dd className="mt-1">Client root</dd></div><div><dt className="text-[var(--text-muted)]">Verification</dt><dd className="mt-1">Confirmed</dd></div></dl>
        </div>
      </section>
    )
  }

  const blocked = state === 'hold-blocked'
  return (
    <section aria-label="Permanent deletion impact" className="min-w-0 flex-1 bg-[var(--surface)] lg:flex lg:min-h-0 lg:flex-col lg:overflow-hidden">
      <RootIdentity longContent={state === 'long-content'} />
      <div className="custom-scrollbar lg:min-h-0 lg:flex-1 lg:overflow-y-auto lg:overscroll-contain">
        <ImpactSummary blocked={blocked} />
        <Consequences />
        <BlockerStatus blocked={blocked} />
        <IncludedHierarchy />
      </div>
    </section>
  )
}

function ProgressStatus({ failed = false }: { failed?: boolean }) {
  const stages = failed
    ? [
        ['Active projections disabled', 'complete'],
        ['Search and derived data removed', 'complete'],
        ['Relationships detached', 'complete'],
        ['Verify and remove unique assets', 'failed'],
        ['Write minimal tombstone', 'waiting'],
      ]
    : [
        ['Active projections disabled', 'complete'],
        ['Search and derived data removed', 'complete'],
        ['Relationships detached', 'current'],
        ['Verify and remove unique assets', 'waiting'],
        ['Write minimal tombstone', 'waiting'],
      ]
  return (
    <div className="p-4 sm:p-5" role="status" aria-live="polite">
      <div className={cn('rounded-[var(--radius-md)] border p-4', failed ? 'border-[var(--danger)] bg-[var(--danger-muted)]' : 'border-[var(--border-subtle)] bg-[var(--bg)]')}>
        <div className="flex items-start gap-3">{failed ? <CircleAlert className="mt-0.5 size-5 shrink-0 text-[var(--danger)]" aria-hidden="true" /> : <Loader2 className="mt-0.5 size-5 shrink-0 animate-spin text-[var(--accent)] motion-reduce:animate-none" aria-hidden="true" />}<div><h3 className="text-sm font-semibold">{failed ? 'Permanent deletion needs attention' : 'Permanent deletion is in progress'}</h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">{failed ? 'A storage verification response was not confirmed. The group remains inaccessible, no storage is reported as freed, and completed stages will not be repeated.' : 'The group is locked and can no longer be restored. This durable operation can resume safely after interruption.'}</p></div></div>
      </div>
      <ol className="mt-4 space-y-2">
        {stages.map(([label, status], index) => (
          <li key={label} className="flex min-h-11 items-center gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] px-3 py-2 text-xs">
            <span className={cn('flex size-6 shrink-0 items-center justify-center rounded-[var(--radius-full)] border font-mono text-[10px]', status === 'complete' && 'border-[var(--success)] text-[var(--success)]', status === 'current' && 'border-[var(--accent)] text-[var(--accent)]', status === 'failed' && 'border-[var(--danger)] text-[var(--danger)]', status === 'waiting' && 'border-[var(--border-strong)] text-[var(--text-muted)]')}>{status === 'complete' ? <Check className="size-3.5" aria-hidden="true" /> : index + 1}</span>
            <span className="min-w-0 flex-1">{label}</span><span className="text-[var(--text-muted)]">{status === 'current' ? 'In progress' : status === 'failed' ? 'Retry required' : status === 'complete' ? 'Complete' : 'Waiting'}</span>
          </li>
        ))}
      </ol>
    </div>
  )
}

function TombstoneStatus() {
  return (
    <div className="p-4 sm:p-5">
      <div className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--bg)] p-4">
        <div className="flex items-start gap-3"><ReceiptText className="mt-0.5 size-5 shrink-0 text-[var(--text-muted)]" aria-hidden="true" /><div><div className="flex flex-wrap items-center gap-2"><h3 className="text-sm font-semibold">This group was permanently deleted</h3><Badge variant="muted">Tombstone only</Badge></div><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">The deleted records and unique files cannot be opened or reconstructed. This view exposes only the minimal content-free receipt required for audit and retry safety.</p></div></div>
        <dl className="mt-4 grid grid-cols-2 gap-3 border-t border-[var(--border-subtle)] pt-4 text-xs"><div><dt className="text-[var(--text-muted)]">Operation</dt><dd className="mt-1 font-mono">OP-418</dd></div><div><dt className="text-[var(--text-muted)]">Completed</dt><dd className="mt-1 font-mono">31 Aug 2026 · 14:18</dd></div><div><dt className="text-[var(--text-muted)]">Result</dt><dd className="mt-1">Verified purge</dd></div><div><dt className="text-[var(--text-muted)]">Receipt</dt><dd className="mt-1 font-mono">TS-7C41…B902</dd></div></dl>
      </div>
    </div>
  )
}

function DecisionPane({
  role,
  state,
  reviewStep,
  typedValue,
  onTypedValueChange,
  onPreviewAuthentication,
}: {
  role: PreviewRole
  state: PreviewState
  reviewStep: ReviewStep
  typedValue: string
  onTypedValueChange: (value: string) => void
  onPreviewAuthentication: () => void
}) {
  const titleRef = useRef<HTMLHeadingElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const readOnly = role !== 'owner-admin'
  const blocked = state === 'hold-blocked'
  const authRequired = state === 'recent-auth-required'
  const impactPending = state === 'impact-pending'
  const exactMatch = typedValue === confirmationCode

  useEffect(() => {
    if (reviewStep === 'confirmation') titleRef.current?.focus()
  }, [reviewStep])

  useEffect(() => {
    if (state === 'impact-ready' && reviewStep === 'confirmation') inputRef.current?.focus()
  }, [state, reviewStep])

  if (state === 'purging') return <ProgressStatus />
  if (state === 'purge-failed') return <ProgressStatus failed />
  if (state === 'purged') return <TombstoneStatus />

  return (
    <div className="p-4 sm:p-5">
      <div className="flex items-start gap-3">
        <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--danger-muted)] text-[var(--danger)]"><LockKeyhole className="size-4" aria-hidden="true" /></span>
        <div className="min-w-0"><h2 ref={titleRef} tabIndex={-1} className="text-section-heading outline-none">{reviewStep === 'impact' ? 'Review before continuing' : 'Confirm permanent deletion'}</h2><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">{reviewStep === 'impact' ? 'Deletion is unavailable until this impact is complete and every safety check passes.' : 'Recent authentication comes first. Exact typed confirmation is the final manual gate.'}</p></div>
      </div>

      <ol className="mt-4 grid grid-cols-2 gap-2" aria-label="Confirmation progress">
        <li className={cn('rounded-[var(--radius-sm)] border p-3 text-xs', reviewStep === 'impact' ? 'border-[var(--accent)] bg-[var(--accent-muted)]' : 'border-[var(--success)] bg-[var(--success-muted)]')}><span className="font-mono">01</span><span className="ml-2 font-semibold">Impact review</span></li>
        <li className={cn('rounded-[var(--radius-sm)] border p-3 text-xs', reviewStep === 'confirmation' ? 'border-[var(--accent)] bg-[var(--accent-muted)]' : 'border-[var(--border-subtle)] bg-[var(--bg)]')}><span className="font-mono">02</span><span className="ml-2 font-semibold">Identity & code</span></li>
      </ol>

      {readOnly ? (
        <div className="mt-4 rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--bg)] p-4" role="status"><div className="flex items-start gap-3"><ShieldAlert className="mt-0.5 size-5 shrink-0 text-[var(--text-muted)]" aria-hidden="true" /><div><div className="flex flex-wrap items-center gap-2"><h3 className="text-sm font-semibold">Permanent deletion is unavailable</h3><Badge variant="muted">{roleLabels[role]}</Badge></div><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Associates and Viewers can inspect this non-mutating impact, but only an Owner or Admin can authenticate and confirm a root-operation purge.</p></div></div></div>
      ) : blocked ? (
        <div className="mt-4 rounded-[var(--radius-md)] border border-[var(--warning)] bg-[var(--warning-muted)] p-4" role="alert"><div className="flex items-start gap-3"><ShieldAlert className="mt-0.5 size-5 shrink-0 text-[var(--warning)]" aria-hidden="true" /><div><h3 className="text-sm font-semibold">Resolve the legal hold first</h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">The whole client group remains protected. Release must happen in the audited Holds workflow; recalculating impact is required afterward.</p></div></div></div>
      ) : impactPending ? (
        <div className="mt-4 rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--bg)] p-4" aria-busy="true" role="status"><div className="flex items-start gap-3"><Loader2 className="mt-0.5 size-5 shrink-0 animate-spin text-[var(--accent)] motion-reduce:animate-none" aria-hidden="true" /><div><h3 className="text-sm font-semibold">Impact calculation is incomplete</h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Shared-file references and one export check are still pending. Confirmation stays disabled and no estimate is treated as final.</p></div></div></div>
      ) : reviewStep === 'impact' ? (
        <div className="mt-4 space-y-3">
          <div className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--bg)] p-4"><h3 className="text-xs font-semibold">Before continuing</h3><ul className="mt-2 space-y-2 text-xs leading-5 text-[var(--text-muted)]"><li className="flex gap-2"><CheckCircle2 className="mt-0.5 size-4 shrink-0 text-[var(--success)]" aria-hidden="true" />Root identity and all 32 included resources were resolved.</li><li className="flex gap-2"><CheckCircle2 className="mt-0.5 size-4 shrink-0 text-[var(--success)]" aria-hidden="true" />Unique and shared storage were calculated separately.</li><li className="flex gap-2"><CheckCircle2 className="mt-0.5 size-4 shrink-0 text-[var(--success)]" aria-hidden="true" />No current hold, export, or dependency blocker was found.</li></ul></div>
        </div>
      ) : (
        <div className="mt-4 space-y-4">
          <div className={cn('rounded-[var(--radius-md)] border p-4', authRequired ? 'border-[var(--warning)] bg-[var(--warning-muted)]' : 'border-[var(--success)] bg-[var(--success-muted)]')}>
            <div className="flex items-start gap-3">{authRequired ? <Fingerprint className="mt-0.5 size-5 shrink-0 text-[var(--warning)]" aria-hidden="true" /> : <ShieldCheck className="mt-0.5 size-5 shrink-0 text-[var(--success)]" aria-hidden="true" />}<div><h3 className="text-sm font-semibold">{authRequired ? 'Recent authentication required' : 'Identity checked recently'}</h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">{authRequired ? 'Authenticate again before the exact-code field becomes available. This preview never asks for or stores a password.' : 'Preview fixture · identity checked at 14:06 · expires in 8 minutes.'}</p></div></div>
            {authRequired && <Button variant="outline" className="mt-3 w-full" onClick={onPreviewAuthentication}><Fingerprint className="size-4" aria-hidden="true" />Preview recent authentication</Button>}
          </div>
          <div>
            <Label htmlFor="permanent-delete-code">Type the exact client code</Label>
            <p id="permanent-delete-help" className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Type <strong className="font-mono font-semibold text-[var(--text-primary)]">{confirmationCode}</strong> to confirm this client root and everything in Trash group OP-418.</p>
            <Input ref={inputRef} id="permanent-delete-code" className="mt-2 font-mono" value={typedValue} onChange={(event) => onTypedValueChange(event.target.value)} disabled={authRequired} aria-describedby="permanent-delete-help permanent-delete-match" autoComplete="off" />
            <p id="permanent-delete-match" className={cn('mt-2 text-xs', exactMatch ? 'text-[var(--success)]' : 'text-[var(--text-muted)]')} aria-live="polite">{exactMatch ? 'Exact code matched. The preview submission is available.' : 'The code must match exactly. Confirmation remains disabled.'}</p>
          </div>
          <div className="rounded-[var(--radius-sm)] border border-[var(--danger)] bg-[var(--danger-muted)] p-3 text-xs leading-5"><strong className="font-semibold">Permanent deletion cannot be undone.</strong> The same dependency-ordered workflow runs for manual and scheduled deletion.</div>
        </div>
      )}
    </div>
  )
}

function DecisionFooter({
  role,
  state,
  reviewStep,
  exactMatch,
  onReviewStepChange,
  onPreviewSubmission,
  onShowBoundary,
}: {
  role: PreviewRole
  state: PreviewState
  reviewStep: ReviewStep
  exactMatch: boolean
  onReviewStepChange: (step: ReviewStep) => void
  onPreviewSubmission: () => void
  onShowBoundary: () => void
}) {
  const readOnly = role !== 'owner-admin'
  const unavailable = state === 'hold-blocked' || state === 'impact-pending' || state === 'purging' || state === 'purged'

  return (
    <div className="shrink-0 border-t border-[var(--border-subtle)] bg-[var(--surface)] p-3">
      {state === 'purge-failed' ? (
        <div className="flex flex-wrap justify-end gap-2"><Button onClick={onShowBoundary}><RefreshCw className="size-4" aria-hidden="true" />Preview safe retry</Button><Button variant="outline" onClick={onShowBoundary}>View operation status</Button></div>
      ) : !readOnly && !unavailable && reviewStep === 'impact' ? (
        <Button className="w-full" onClick={() => onReviewStepChange('confirmation')}><Fingerprint className="size-4" aria-hidden="true" />Continue to identity check</Button>
      ) : !readOnly && !unavailable && reviewStep === 'confirmation' ? (
        <div className="grid gap-2"><Button variant="destructive" className="min-h-11 w-full border border-[var(--danger)]" disabled={!exactMatch || state === 'recent-auth-required'} onClick={onPreviewSubmission}><Trash2 className="size-4" aria-hidden="true" />Delete client group permanently</Button><Button variant="outline" className="w-full" onClick={() => onReviewStepChange('impact')}><ArrowLeft className="size-4" aria-hidden="true" />Back to impact review</Button></div>
      ) : (
        <p className="text-xs leading-5 text-[var(--text-muted)]">{state === 'purging' ? 'This durable operation can resume safely; restoration is no longer available.' : state === 'purged' ? 'Only the minimal content-free audit receipt remains.' : readOnly ? `${roleLabels[role]} access remains read only.` : 'Permanent deletion remains unavailable until this state is resolved.'}</p>
      )}
      <p className="mt-2 text-xs leading-5 text-[var(--text-muted)]">Concept controls never submit deletion or claim that storage was freed.</p>
    </div>
  )
}

function LoadingState() {
  return (
    <div className="grid h-full min-h-[32rem] lg:grid-cols-[minmax(0,1fr)_24rem]" aria-busy="true" aria-live="polite">
      <p className="sr-only">Calculating permanent deletion impact…</p>
      <div className="space-y-4 bg-[var(--surface)] p-4 sm:p-5"><div className="flex gap-3"><Skeleton className="size-10 shrink-0" /><div className="flex-1"><Skeleton className="h-3 w-32" /><Skeleton className="mt-2 h-5 w-3/5" /><Skeleton className="mt-2 h-3 w-44" /></div></div><div className="grid grid-cols-2 gap-2 sm:grid-cols-4">{[1, 2, 3, 4].map((item) => <Skeleton key={item} className="h-20" />)}</div>{[1, 2, 3].map((item) => <Skeleton key={item} className="h-32" />)}</div>
      <div className="border-t border-[var(--border-subtle)] bg-[var(--surface)] p-4 lg:border-l lg:border-t-0 sm:p-5"><Skeleton className="h-5 w-48" /><Skeleton className="mt-2 h-3 w-4/5" /><div className="mt-5 grid grid-cols-2 gap-2"><Skeleton className="h-16" /><Skeleton className="h-16" /></div><Skeleton className="mt-4 h-36" /></div>
    </div>
  )
}

function EmptyState() {
  return <div className="grid min-h-[32rem] place-items-center bg-[var(--surface)] p-6 text-center"><div><Trash2 className="mx-auto size-8 text-[var(--text-muted)]" aria-hidden="true" /><h1 className="mt-3 text-section-heading">No Trash group selected</h1><p className="mx-auto mt-2 max-w-md text-sm leading-6 text-[var(--text-muted)]">Select a direct root operation in Trash before reviewing permanent deletion. Inherited children never open this workflow independently.</p><a href="/dev/trash-workspace-concept" className="mt-4 inline-flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] px-3 text-sm font-medium text-[var(--primary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"><ArrowLeft className="size-4" aria-hidden="true" />Return to Trash concept</a></div></div>
}

function ErrorState({ onRetry }: { onRetry: () => void }) {
  return <div className="grid min-h-[32rem] place-items-center bg-[var(--surface)] p-6 text-center" role="alert"><div><CircleAlert className="mx-auto size-8 text-[var(--danger)]" aria-hidden="true" /><h1 className="mt-3 text-section-heading">Impact could not be displayed</h1><p className="mx-auto mt-2 max-w-md text-sm leading-6 text-[var(--text-muted)]">Permanent deletion remains unavailable because the root, dependency, and shared-asset checks did not load completely.</p><Button variant="outline" className="mt-4" onClick={onRetry}><RefreshCw className="size-4" aria-hidden="true" />Calculate impact again</Button></div></div>
}

function ConceptBoundaryDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent><DialogHeader><DialogTitle>Permanent-delete concept only</DialogTitle><DialogDescription>This fixture illustrates the approved root-operation impact, confirmation, durable execution, and tombstone states for visual review.</DialogDescription></DialogHeader><div className="flex items-start gap-2 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3 text-sm leading-6 text-[var(--text-secondary)]"><Info className="mt-1 size-4 shrink-0" aria-hidden="true" /><span>There are no API calls, server actions, permission claims, authentication requests, purge jobs, asset deletions, or data writes. Preview controls change local browser state only.</span></div><DialogFooter><Button onClick={() => onOpenChange(false)}>Close concept note</Button></DialogFooter></DialogContent></Dialog>
}

function SubmissionPreviewDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent><DialogHeader><DialogTitle>Production would schedule the purge here</DialogTitle><DialogDescription>The concept stops before any mutation and does not claim that deletion happened.</DialogDescription></DialogHeader><div className="rounded-[var(--radius-sm)] border border-[var(--danger)] bg-[var(--danger-muted)] p-3 text-sm leading-6 text-[var(--text-secondary)]"><AlertTriangle className="mr-2 inline size-4 text-[var(--danger)]" aria-hidden="true" />A live workflow would record durable intent, lock restoration, run the verified dependency stages, reconcile retries, and expose operation status.</div><DialogFooter><Button variant="outline" onClick={() => onOpenChange(false)}>Return to concept</Button><Button variant="destructive" disabled>Delete client group permanently</Button></DialogFooter></DialogContent></Dialog>
}

export function TrashPermanentDeleteConcept() {
  const [role, setRole] = useState<PreviewRole>('owner-admin')
  const [previewState, setPreviewState] = useState<PreviewState>('impact-ready')
  const [reviewStep, setReviewStep] = useState<ReviewStep>('impact')
  const [typedValue, setTypedValue] = useState('')
  const [boundaryOpen, setBoundaryOpen] = useState(false)
  const [submissionOpen, setSubmissionOpen] = useState(false)
  const { setTheme } = useTheme()

  const stateBadge = useMemo(() => {
    if (previewState === 'hold-blocked' || previewState === 'impact-pending') return { label: stateLabels[previewState], variant: 'warning' as const }
    if (previewState === 'purge-failed' || previewState === 'error') return { label: stateLabels[previewState], variant: 'danger' as const }
    if (previewState === 'purging') return { label: stateLabels[previewState], variant: 'default' as const }
    if (previewState === 'purged') return { label: stateLabels[previewState], variant: 'muted' as const }
    return { label: stateLabels[previewState], variant: 'outline' as const }
  }, [previewState])

  const changeState = (state: PreviewState) => {
    setPreviewState(state)
    setReviewStep(state === 'recent-auth-required' ? 'confirmation' : 'impact')
    setTypedValue('')
  }

  return (
    <div className="flex h-dvh overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]">
      <aside aria-label="Application context" className="hidden w-16 shrink-0 flex-col items-center border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] py-3 text-[var(--sidebar-text)] lg:flex"><span className="flex size-10 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]"><Gavel className="size-5" aria-hidden="true" /></span><span className="mt-auto flex size-11 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]" aria-label="Trash"><Trash2 className="size-5" aria-hidden="true" /></span></aside>
      <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <header className="shrink-0 border-b border-[var(--border)] bg-[var(--surface)]">
          <div className="flex min-h-12 items-center gap-2 border-b border-[var(--border-subtle)] px-3 text-xs text-[var(--text-muted)] sm:px-4"><span className="hidden sm:inline">Apex Tax Advocates</span><ChevronRight className="hidden size-3.5 sm:block" aria-hidden="true" /><a href="/dev/trash-workspace-concept" className="inline-flex min-h-11 items-center gap-1 font-medium text-[var(--text-secondary)] hover:text-[var(--text-primary)] sm:min-h-0"><ArrowLeft className="size-3.5 sm:hidden" aria-hidden="true" />Trash</a><ChevronRight className="size-3.5" aria-hidden="true" /><span className="truncate text-[var(--text-primary)]">Permanent deletion review</span><Badge variant="muted" className="ml-auto">Concept only</Badge></div>
          <div className="flex min-h-14 flex-wrap items-center gap-2 px-3 py-1.5 sm:flex-nowrap sm:px-4 sm:py-0"><div className="flex min-w-0 items-center gap-2"><DatabaseZap className="size-4 shrink-0 text-[var(--danger)]" aria-hidden="true" /><span className="truncate text-sm font-semibold">Root-operation permanent delete</span></div><Badge variant={stateBadge.variant} className="hidden sm:inline-flex">{stateBadge.label}</Badge><div className="ml-auto"><PreviewMenu role={role} state={previewState} onRoleChange={(nextRole) => { setRole(nextRole); setTypedValue('') }} onStateChange={changeState} onAppearanceChange={setTheme} onShowBoundary={() => setBoundaryOpen(true)} /></div></div>
        </header>
        <div className="shrink-0 border-b border-[var(--danger)] bg-[var(--danger-muted)] px-3 py-2.5 sm:px-4" role="note"><div className="flex items-start gap-2 text-xs leading-5"><AlertTriangle className="mt-0.5 size-4 shrink-0 text-[var(--danger)]" aria-hidden="true" /><p><strong className="font-semibold">Permanent deletion cannot be undone.</strong> Manual and scheduled deletion use this same verified workflow. Shared assets remain when another record, Intake item, export, or hold still references them.</p></div></div>

        <div aria-label="Permanent deletion review workspace" className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain lg:overflow-hidden">
          {previewState === 'loading' ? <LoadingState /> : previewState === 'empty' ? <EmptyState /> : previewState === 'error' ? <ErrorState onRetry={() => changeState('impact-ready')} /> : (
            <div className="min-h-full lg:flex lg:h-full lg:min-h-0">
              <ImpactPane state={previewState} />
              <aside aria-label="Permanent deletion decision" className="border-t border-[var(--border-subtle)] bg-[var(--surface)] lg:flex lg:w-96 lg:shrink-0 lg:flex-col lg:border-l lg:border-t-0">
                <div className="hidden h-14 shrink-0 items-center gap-2 border-b border-[var(--border-subtle)] px-4 lg:flex"><LockKeyhole className="size-4 text-[var(--danger)]" aria-hidden="true" /><span className="text-sm font-semibold">Decision & operation status</span></div>
                <div className="custom-scrollbar lg:min-h-0 lg:flex-1 lg:overflow-y-auto lg:overscroll-contain"><DecisionPane role={role} state={previewState} reviewStep={reviewStep} typedValue={typedValue} onTypedValueChange={setTypedValue} onPreviewAuthentication={() => { setPreviewState('impact-ready'); setReviewStep('confirmation'); setTypedValue('') }} /></div>
                <DecisionFooter role={role} state={previewState} reviewStep={reviewStep} exactMatch={typedValue === confirmationCode} onReviewStepChange={setReviewStep} onPreviewSubmission={() => setSubmissionOpen(true)} onShowBoundary={() => setBoundaryOpen(true)} />
              </aside>
            </div>
          )}
        </div>
      </main>
      <ConceptBoundaryDialog open={boundaryOpen} onOpenChange={setBoundaryOpen} />
      <SubmissionPreviewDialog open={submissionOpen} onOpenChange={setSubmissionOpen} />
    </div>
  )
}
