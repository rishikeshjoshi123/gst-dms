'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import { useTheme } from 'next-themes'
import {
  AlertCircle,
  ArrowLeft,
  CalendarClock,
  Check,
  ChevronDown,
  ChevronRight,
  CircleDollarSign,
  FileQuestion,
  FileSearch,
  Filter,
  FolderInput,
  Gavel,
  GitCompareArrows,
  Info,
  ListChecks,
  LockKeyhole,
  Moon,
  MoreHorizontal,
  RefreshCw,
  Search,
  ShieldCheck,
  Sun,
  X,
} from 'lucide-react'

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
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { cn } from '@/lib/utils'

type Role = 'owner_admin' | 'associate' | 'viewer'
type PreviewState = 'default' | 'loading' | 'empty' | 'error' | 'long_content' | 'stale'
type ReviewType = 'extraction_conflict' | 'ambiguous_placement' | 'relationship_conflict' | 'deadline_verification' | 'financial_verification'
type ReviewStatus = 'open' | 'in_progress' | 'superseded'
type Priority = 'normal' | 'high' | 'urgent'
type QueueScope = 'all' | 'mine' | 'unassigned'
type TypeFilter = 'all' | ReviewType
type StatusFilter = 'active' | 'open' | 'in_progress' | 'superseded' | 'all'
type EvidenceAccess = 'available' | 'partial' | 'stale'
type EvidenceKind = 'source_quote' | 'document_fact' | 'comparison' | 'matter_context'

type Evidence = {
  id: string
  kind: EvidenceKind
  label: string
  locator: string
  excerpt: string
  access: EvidenceAccess
}

type DecisionOption = {
  id: string
  label: string
  explanation: string
}

type TypedDecision =
  | { kind: 'select_extracted_value'; label: string; instruction: string; options: DecisionOption[] }
  | { kind: 'select_matter_placement'; label: string; instruction: string; options: DecisionOption[] }
  | { kind: 'confirm_document_relationship'; label: string; instruction: string; options: DecisionOption[] }
  | { kind: 'verify_deadline'; label: string; instruction: string; options: DecisionOption[] }
  | { kind: 'verify_financial_entry'; label: string; instruction: string; options: DecisionOption[] }

type ReviewItem = {
  id: string
  type: ReviewType
  typeLabel: string
  title: string
  reason: string
  impact: string
  age: string
  owner: string | null
  evidenceAvailability: 'Complete' | 'Partial' | 'Stale'
  status: ReviewStatus
  priority: Priority
  client: string
  matter: string
  document: string
  sourceVersion: string
  revision: number
  evidence: Evidence[]
  decision: TypedDecision
  associateCanResolve: boolean
  replacementId?: string
  longContent?: boolean
}

const reviewFixtures: ReviewItem[] = [
  {
    id: 'review-ext-204',
    type: 'extraction_conflict',
    typeLabel: 'Extraction conflict',
    title: 'Two supported invoice totals disagree',
    reason: 'The invoice summary and signed annexure support different taxable totals.',
    impact: 'The selected value will update the effective invoice total used by the appeal working papers.',
    age: '42 minutes',
    owner: 'Rishikesh Joshi',
    evidenceAvailability: 'Complete',
    status: 'in_progress',
    priority: 'urgent',
    client: 'Apex Auto Components Private Limited',
    matter: 'FY 2023–24 ITC mismatch appeal',
    document: 'Supplier invoice reconciliation — signed.pdf',
    sourceVersion: 'Document version 8',
    revision: 4,
    evidence: [
      { id: 'ext-quote-1', kind: 'source_quote', label: 'Signed annexure · page 14', locator: 'Page 14 · table total', excerpt: 'Taxable value total: ₹18,42,780.00', access: 'available' },
      { id: 'ext-quote-2', kind: 'source_quote', label: 'Invoice summary · page 2', locator: 'Page 2 · summary block', excerpt: 'Aggregate taxable value: ₹18,24,780.00', access: 'available' },
      { id: 'ext-compare', kind: 'comparison', label: 'Conflict fact', locator: 'Typed comparison', excerpt: 'Difference: ₹18,000.00. Both candidates are supported by visible source text.', access: 'available' },
    ],
    decision: {
      kind: 'select_extracted_value',
      label: 'Choose invoice total',
      instruction: 'Choose the value that the effective invoice metadata should use. The evidence remains attached to the recorded decision.',
      options: [
        { id: 'annexure-total', label: 'Use ₹18,42,780.00', explanation: 'Supported by the signed annexure on page 14.' },
        { id: 'summary-total', label: 'Use ₹18,24,780.00', explanation: 'Supported by the invoice summary on page 2.' },
        { id: 'return-source', label: 'Return for source correction', explanation: 'Use when neither candidate can safely become effective.' },
      ],
    },
    associateCanResolve: true,
  },
  {
    id: 'review-place-118',
    type: 'ambiguous_placement',
    typeLabel: 'Ambiguous placement',
    title: 'Reply references two active matters',
    reason: 'The GSTIN and notice reference match one matter each, so ordinary intake placement cannot decide safely.',
    impact: 'The chosen placement controls Matter lineage, access context, retention grouping, and downstream evidence discovery.',
    age: '3 hours',
    owner: null,
    evidenceAvailability: 'Complete',
    status: 'open',
    priority: 'high',
    client: 'Mehta Industrial Works',
    matter: 'Placement not yet decided',
    document: 'Reply to DRC-01A dated 29 August 2026.pdf',
    sourceVersion: 'Staged source version 3',
    revision: 2,
    evidence: [
      { id: 'place-notice', kind: 'source_quote', label: 'Notice reference', locator: 'Page 1 · heading', excerpt: 'Reference: ZD290826041771M', access: 'available' },
      { id: 'place-matter-a', kind: 'matter_context', label: 'Candidate matter A', locator: 'MIW-DRC-2026-04', excerpt: 'DRC-01 reply and hearing · exact notice-reference match', access: 'available' },
      { id: 'place-matter-b', kind: 'matter_context', label: 'Candidate matter B', locator: 'MIW-ITC-2026-02', excerpt: 'ITC reconciliation · exact GSTIN and tax-period match', access: 'available' },
    ],
    decision: {
      kind: 'select_matter_placement',
      label: 'Assign matter placement',
      instruction: 'Choose one authorised destination or return the item to the permitted intake queue. This is not an ordinary waiting-for-assignment row.',
      options: [
        { id: 'matter-a', label: 'Place in DRC-01 reply and hearing', explanation: 'Uses the exact notice-reference match.' },
        { id: 'matter-b', label: 'Place in ITC reconciliation', explanation: 'Uses the GSTIN and tax-period match.' },
        { id: 'intake-return', label: 'Return to intake with reason', explanation: 'Keeps the staged source unplaced for additional evidence.' },
      ],
    },
    associateCanResolve: true,
  },
  {
    id: 'review-link-076',
    type: 'relationship_conflict',
    typeLabel: 'Relationship conflict',
    title: 'Order may respond to one of two notices',
    reason: 'The order cites a shared proceeding number but omits the original notice reference.',
    impact: 'Confirming the relationship changes the procedural sequence shown in the Matter workspace.',
    age: '1 day',
    owner: 'Ananya Kapoor',
    evidenceAvailability: 'Partial',
    status: 'open',
    priority: 'normal',
    client: 'Suryodaya Textiles Limited',
    matter: 'Classification appeal — woven technical fabrics',
    document: 'Order-in-Original 61/2026.pdf',
    sourceVersion: 'Document version 2',
    revision: 1,
    evidence: [
      { id: 'link-order', kind: 'source_quote', label: 'Order reference', locator: 'Page 1 · subject', excerpt: 'Proceedings arising from SCN classification dispute for FY 2024–25.', access: 'available' },
      { id: 'link-notice-a', kind: 'document_fact', label: 'Candidate notice 1', locator: 'SCN 18/2026 · version 5', excerpt: 'Classification dispute · FY 2024–25 · same proceeding number', access: 'available' },
      { id: 'link-notice-b', kind: 'document_fact', label: 'Candidate notice 2', locator: 'SCN 22/2026 · version 1', excerpt: 'Valuation addendum · FY 2024–25 · source quotation unavailable', access: 'partial' },
    ],
    decision: {
      kind: 'confirm_document_relationship',
      label: 'Confirm order relationship',
      instruction: 'Choose the source notice this order responds to, or record that the relationship is unsupported.',
      options: [
        { id: 'notice-a', label: 'Relate to SCN 18/2026', explanation: 'The proceeding number and classification subject agree.' },
        { id: 'notice-b', label: 'Relate to SCN 22/2026', explanation: 'The tax period agrees, but source evidence is partial.' },
        { id: 'unsupported', label: 'No supported relationship', explanation: 'Leaves both documents unlinked and records the reason.' },
      ],
    },
    associateCanResolve: true,
  },
  {
    id: 'review-deadline-031',
    type: 'deadline_verification',
    typeLabel: 'Deadline verification',
    title: 'Verify appeal filing deadline from service evidence',
    reason: 'The order date and portal service date produce different filing dates under the configured rule.',
    impact: 'The verified date becomes the accountable deadline and may trigger assigned deadline reminders.',
    age: '2 days',
    owner: 'Rishikesh Joshi',
    evidenceAvailability: 'Complete',
    status: 'open',
    priority: 'urgent',
    client: 'Kaveri Components Private Limited',
    matter: 'FY 2024–25 ITC reconciliation',
    document: 'Order acknowledgement and portal receipt bundle.pdf',
    sourceVersion: 'Evidence bundle version 6',
    revision: 3,
    evidence: [
      { id: 'deadline-order', kind: 'source_quote', label: 'Order date', locator: 'Order · page 28', excerpt: 'Dated: 06 August 2026', access: 'available' },
      { id: 'deadline-service', kind: 'source_quote', label: 'Portal service receipt', locator: 'Receipt · page 2', excerpt: 'Communicated on portal: 11 August 2026 at 18:42 IST', access: 'available' },
      { id: 'deadline-rule', kind: 'matter_context', label: 'Configured deadline rule', locator: 'Appeal filing · revision 7', excerpt: 'Thirty days from verified service date; organisation timezone Asia/Kolkata.', access: 'available' },
    ],
    decision: {
      kind: 'verify_deadline',
      label: 'Verify deadline date',
      instruction: 'Choose the supported date or return the deadline as provisional. Date calculation remains a typed deadline-domain decision.',
      options: [
        { id: 'service-derived', label: 'Verify 10 September 2026', explanation: 'Calculated from the portal service date under rule revision 7.' },
        { id: 'order-derived', label: 'Verify 05 September 2026', explanation: 'Calculated from the order date; requires a reason for rejecting service evidence.' },
        { id: 'keep-provisional', label: 'Keep provisional', explanation: 'No accountable reminder is created until evidence is sufficient.' },
      ],
    },
    associateCanResolve: true,
  },
  {
    id: 'review-financial-044',
    type: 'financial_verification',
    typeLabel: 'Financial verification',
    title: 'Verify disputed tax and interest allocation',
    reason: 'The demand table total agrees, but tax and interest components conflict with the signed computation sheet.',
    impact: 'The verified allocation changes the Matter financial summary; internal-cost authority is required.',
    age: '4 days',
    owner: 'Meera Shah',
    evidenceAvailability: 'Complete',
    status: 'open',
    priority: 'high',
    client: 'Western Freight Services',
    matter: 'E-way bill penalty response',
    document: 'Demand order and computation sheet.pdf',
    sourceVersion: 'Document version 4',
    revision: 6,
    evidence: [
      { id: 'finance-order', kind: 'source_quote', label: 'Demand order', locator: 'Page 17 · demand table', excerpt: 'Tax ₹8,60,000 · Interest ₹1,24,600 · Total ₹9,84,600', access: 'available' },
      { id: 'finance-sheet', kind: 'source_quote', label: 'Signed computation', locator: 'Page 21 · signed schedule', excerpt: 'Tax ₹8,42,000 · Interest ₹1,42,600 · Total ₹9,84,600', access: 'available' },
      { id: 'finance-compare', kind: 'comparison', label: 'Conflict fact', locator: 'Typed financial comparison', excerpt: 'The total agrees; ₹18,000 is allocated to different components.', access: 'available' },
    ],
    decision: {
      kind: 'verify_financial_entry',
      label: 'Verify financial allocation',
      instruction: 'An Owner/Admin with financial authority must choose the supported component allocation. Associates may inspect the evidence only.',
      options: [
        { id: 'order-allocation', label: 'Use demand-order allocation', explanation: 'Tax ₹8,60,000 · Interest ₹1,24,600.' },
        { id: 'signed-allocation', label: 'Use signed-computation allocation', explanation: 'Tax ₹8,42,000 · Interest ₹1,42,600.' },
        { id: 'return-financial', label: 'Return for financial reconciliation', explanation: 'Keeps the entry provisional and records the unresolved conflict.' },
      ],
    },
    associateCanResolve: false,
  },
  {
    id: 'review-old-019',
    type: 'extraction_conflict',
    typeLabel: 'Extraction conflict',
    title: 'Superseded GSTIN candidate from an earlier document version',
    reason: 'A corrected source version was uploaded after this evidence snapshot was created.',
    impact: 'No decision can apply to the current document; the replacement item owns any remaining conflict.',
    age: '6 days',
    owner: 'Ananya Kapoor',
    evidenceAvailability: 'Stale',
    status: 'superseded',
    priority: 'normal',
    client: 'Apex Auto Components Private Limited',
    matter: 'FY 2023–24 ITC mismatch appeal',
    document: 'Supplier declaration — superseded version.pdf',
    sourceVersion: 'Document version 3 · no longer current',
    revision: 5,
    evidence: [
      { id: 'old-gstin', kind: 'source_quote', label: 'Superseded quotation', locator: 'Version 3 · page 1', excerpt: 'GSTIN: 27AAECA1842M1Z7', access: 'stale' },
      { id: 'new-gstin', kind: 'document_fact', label: 'Current source fact', locator: 'Version 4 · page 1', excerpt: 'Corrected source version is current. Evidence refresh is required before any decision.', access: 'available' },
    ],
    decision: {
      kind: 'select_extracted_value',
      label: 'No decision — superseded',
      instruction: 'This historical evidence is read-only. A current replacement item must be opened instead of applying an outdated choice.',
      options: [],
    },
    associateCanResolve: false,
    replacementId: 'review-ext-204',
  },
  {
    id: 'review-long-507',
    type: 'ambiguous_placement',
    typeLabel: 'Ambiguous placement',
    title: 'Place the consolidated reply, annexures, transport schedules, supplier confirmations, reconciliation workbook, and signed authorisation for an exceptionally long legal entity name',
    reason: 'Long-content fixture: the uploaded bundle contains two valid GST registrations, three proceeding references, and a manually amended covering letter whose full text must remain available without widening the queue or detail pane.',
    impact: 'Long-content fixture: placement determines the canonical Matter lineage for the full bundle, future search locators, retention grouping, deadline evidence, document relationships, and authorised Matter context; no part of this explanation may create page-level horizontal overflow.',
    age: '8 days',
    owner: 'Rishikesh Joshi',
    evidenceAvailability: 'Partial',
    status: 'in_progress',
    priority: 'high',
    client: 'Shree Venkateshwara Precision Components and Renewable Energy Systems Private Limited',
    matter: 'Consolidated FY 2024–25 proceedings, supplier-confirmation reconciliation, transport evidence, and appeal preparation',
    document: 'Consolidated reply with annexures, schedules, reconciliations, signed authority, and supporting evidence — final reviewed bundle.pdf',
    sourceVersion: 'Staged source version 11',
    revision: 9,
    evidence: [
      { id: 'long-cover', kind: 'source_quote', label: 'Amended covering letter with a deliberately long evidence label that must wrap naturally', locator: 'Page 1 · paragraphs 2–5', excerpt: 'The reply consolidates the classification proceeding, transport-penalty response, and supplier-confirmation reconciliation while preserving their separate notice references and reporting periods.', access: 'available' },
      { id: 'long-annexures', kind: 'comparison', label: 'Three candidate Matter lineages', locator: 'Typed placement comparison · revision 9', excerpt: 'Candidate A matches the classification notice, candidate B matches the transport schedule, and candidate C matches the reporting period. The signed authority names the client but does not identify one proceeding.', access: 'partial' },
      { id: 'long-missing', kind: 'document_fact', label: 'Missing evidence', locator: 'Annexure index · item 17', excerpt: 'The referenced departmental acknowledgement is not present in the uploaded bundle.', access: 'partial' },
    ],
    decision: {
      kind: 'select_matter_placement',
      label: 'Assign bundle placement',
      instruction: 'Choose one canonical Matter or return the bundle to the permitted intake queue with a reason. The preview preserves full labels and evidence text at narrow widths.',
      options: [
        { id: 'long-a', label: 'Place in Classification appeal — woven technical fabrics and connected supplier evidence', explanation: 'Best notice-reference match; transport evidence would remain supporting material.' },
        { id: 'long-b', label: 'Place in E-way bill penalty response with consolidated transport schedules', explanation: 'Best annexure match; classification evidence would remain supporting material.' },
        { id: 'long-return', label: 'Return the consolidated bundle to intake for separation and evidence completion', explanation: 'No canonical records are changed while the bundle is separated.' },
      ],
    },
    associateCanResolve: true,
    longContent: true,
  },
]

const statusLabels: Record<ReviewStatus, string> = {
  open: 'Open',
  in_progress: 'In progress',
  superseded: 'Superseded',
}

const statusVariants: Record<ReviewStatus, 'warning' | 'default' | 'muted'> = {
  open: 'warning',
  in_progress: 'default',
  superseded: 'muted',
}

const typeIcons: Record<ReviewType, typeof FileSearch> = {
  extraction_conflict: FileSearch,
  ambiguous_placement: FolderInput,
  relationship_conflict: GitCompareArrows,
  deadline_verification: CalendarClock,
  financial_verification: CircleDollarSign,
}

const evidenceKindLabels: Record<EvidenceKind, string> = {
  source_quote: 'Source quotation',
  document_fact: 'Document fact',
  comparison: 'Typed comparison',
  matter_context: 'Matter context',
}

const previewLabels: Record<PreviewState, string> = {
  default: 'Default queue',
  loading: 'Loading',
  empty: 'Empty',
  error: 'Error',
  long_content: 'Long content',
  stale: 'Stale / superseded',
}

function ConceptRail() {
  return (
    <aside className="hidden h-full w-16 shrink-0 flex-col overflow-hidden border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] text-[var(--sidebar-text)] md:flex" aria-label="Primary navigation preview">
        <div className="flex h-14 shrink-0 items-center border-b border-[var(--sidebar-border,var(--border))] px-4">
          <Gavel className="size-5 shrink-0 text-[var(--sidebar-accent)]" aria-hidden="true" />
        </div>
        <div className="px-2 py-4">
          <button type="button" aria-current="page" aria-label="Review" title="Review" className="flex min-h-11 w-full items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)] outline-none focus-visible:ring-2 focus-visible:ring-[var(--sidebar-accent)]">
            <ListChecks className="size-4 shrink-0" aria-hidden="true" />
          </button>
        </div>
    </aside>
  )
}

function FilterMenu<T extends string>({ label, value, options, onChange }: { label: string; value: T; options: Array<{ value: T; label: string }>; onChange: (value: T) => void }) {
  const current = options.find((option) => option.value === value)?.label ?? label
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" className="min-h-11 min-w-0 lg:min-h-8">
          <Filter className="size-4 shrink-0" aria-hidden="true" />
          <span className="truncate">{current}</span>
          <ChevronDown className="size-3.5 shrink-0" aria-hidden="true" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start">
        <DropdownMenuLabel>{label}</DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuRadioGroup value={value} onValueChange={(next) => onChange(next as T)}>
          {options.map((option) => <DropdownMenuRadioItem key={option.value} value={option.value}>{option.label}</DropdownMenuRadioItem>)}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function PreviewMenu({ state, role, onState, onRole }: { state: PreviewState; role: Role; onState: (state: PreviewState) => void; onRole: (role: Role) => void }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm"><Info className="size-4" aria-hidden="true" />Preview<ChevronDown className="size-3.5" aria-hidden="true" /></Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-60">
        <DropdownMenuLabel>Fixture state</DropdownMenuLabel>
        <DropdownMenuRadioGroup value={state} onValueChange={(value) => onState(value as PreviewState)}>
          {(Object.entries(previewLabels) as Array<[PreviewState, string]>).map(([value, label]) => <DropdownMenuRadioItem key={value} value={value}>{label}</DropdownMenuRadioItem>)}
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <DropdownMenuLabel>Permission state</DropdownMenuLabel>
        <DropdownMenuRadioGroup value={role} onValueChange={(value) => onRole(value as Role)}>
          <DropdownMenuRadioItem value="owner_admin">Owner / Admin · all decisions</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="associate">Associate · permitted decisions</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="viewer">Viewer · read only</DropdownMenuRadioItem>
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function WorkspaceHeader({ state, role, dark, onState, onRole, onDark, onAbout }: { state: PreviewState; role: Role; dark: boolean; onState: (state: PreviewState) => void; onRole: (role: Role) => void; onDark: () => void; onAbout: () => void }) {
  const roleLabel = role === 'owner_admin' ? 'Owner / Admin' : role === 'viewer' ? 'Viewer · read only' : 'Associate'
  return (
    <header className="flex h-14 shrink-0 items-center gap-3 border-b border-[var(--border)] bg-[var(--surface)] px-3 md:px-5">
      <div className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--bg-overlay)] text-[var(--text-secondary)] md:hidden"><ListChecks className="size-4" aria-hidden="true" /></div>
      <div className="min-w-0 flex-1">
        <div className="flex min-w-0 items-center gap-2"><span className="hidden text-xs text-[var(--text-muted)] sm:inline">Apex Tax Advocates</span><ChevronRight className="hidden size-3 text-[var(--text-muted)] sm:block" aria-hidden="true" /><h1 className="truncate text-lg font-semibold">Review</h1></div>
        <p className="truncate text-xs text-[var(--text-muted)]">Human decisions with typed evidence and one owning resolver</p>
      </div>
      <Badge variant="warning" className="hidden shrink-0 lg:inline-flex"><ShieldCheck className="size-3" aria-hidden="true" />Fixture only</Badge>
      <Badge variant={role === 'viewer' ? 'muted' : 'outline'} className="hidden shrink-0 sm:inline-flex"><LockKeyhole className="size-3" aria-hidden="true" />{roleLabel}</Badge>
      <PreviewMenu state={state} role={role} onState={onState} onRole={onRole} />
      <DropdownMenu>
        <DropdownMenuTrigger asChild><Button variant="ghost" size="icon" aria-label="More preview controls"><MoreHorizontal className="size-4" aria-hidden="true" /></Button></DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onSelect={onDark}>{dark ? <Sun className="size-4" aria-hidden="true" /> : <Moon className="size-4" aria-hidden="true" />}{dark ? 'Use light appearance' : 'Use dark appearance'}</DropdownMenuItem>
          <DropdownMenuItem onSelect={onAbout}><Info className="size-4" aria-hidden="true" />About this fixture</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </header>
  )
}

function QueueWorkbar({ query, scope, type, status, count, onQuery, onScope, onType, onStatus }: { query: string; scope: QueueScope; type: TypeFilter; status: StatusFilter; count: number; onQuery: (value: string) => void; onScope: (value: QueueScope) => void; onType: (value: TypeFilter) => void; onStatus: (value: StatusFilter) => void }) {
  return (
    <div className="shrink-0 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 py-2 lg:px-4">
      <div className="flex min-w-0 flex-col gap-2 xl:flex-row xl:items-center">
        <label className="relative min-w-0 flex-1 xl:max-w-sm">
          <span className="sr-only">Search Review queue fixtures</span>
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
          <Input value={query} onChange={(event) => onQuery(event.target.value)} placeholder="Search Review queue" className="pl-9" />
        </label>
        <div className="grid min-w-0 grid-cols-2 gap-2 sm:grid-cols-3 xl:flex">
          <FilterMenu label="Ownership" value={scope} onChange={onScope} options={[{ value: 'all', label: 'All owners' }, { value: 'mine', label: 'Assigned to me' }, { value: 'unassigned', label: 'Unassigned' }]} />
          <FilterMenu label="Review type" value={type} onChange={onType} options={[{ value: 'all', label: 'All types' }, { value: 'extraction_conflict', label: 'Extraction' }, { value: 'ambiguous_placement', label: 'Placement' }, { value: 'relationship_conflict', label: 'Relationship' }, { value: 'deadline_verification', label: 'Deadline' }, { value: 'financial_verification', label: 'Financial' }]} />
          <FilterMenu label="Lifecycle" value={status} onChange={onStatus} options={[{ value: 'active', label: 'Active only' }, { value: 'open', label: 'Open' }, { value: 'in_progress', label: 'In progress' }, { value: 'superseded', label: 'Superseded' }, { value: 'all', label: 'All states' }]} />
        </div>
        <p className="shrink-0 text-xs text-[var(--text-muted)]" aria-live="polite">{count} {count === 1 ? 'item' : 'items'}</p>
      </div>
    </div>
  )
}

function PriorityLabel({ priority }: { priority: Priority }) {
  return <span className={cn('text-xs font-medium capitalize', priority === 'urgent' && 'text-[var(--danger)]', priority === 'high' && 'text-[var(--warning)]', priority === 'normal' && 'text-[var(--text-muted)]')}>{priority}</span>
}

function Fact({ label, children, wide = false }: { label: string; children: React.ReactNode; wide?: boolean }) {
  return <div className={cn('min-w-0', wide && 'sm:col-span-2')}><dt className="text-[11px] font-medium uppercase tracking-wide text-[var(--text-muted)]">{label}</dt><dd className="mt-0.5 break-words text-xs leading-5 text-[var(--text-secondary)]">{children}</dd></div>
}

function MobileQueueRow({ item, selected, onSelect }: { item: ReviewItem; selected: boolean; onSelect: () => void }) {
  const Icon = typeIcons[item.type]
  return (
    <button type="button" onClick={onSelect} className={cn('w-full border-b border-[var(--border-subtle)] bg-[var(--surface)] p-3 text-left transition-colors hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent)]', selected && 'bg-[var(--accent-muted)]')}>
        <div className="flex min-w-0 items-start gap-3">
          <span className="flex size-8 shrink-0 items-center justify-center rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--bg-overlay)] text-[var(--text-secondary)]"><Icon className="size-4" aria-hidden="true" /></span>
          <div className="min-w-0 flex-1">
            <div className="flex min-w-0 flex-wrap items-center gap-2"><span className="text-xs font-medium text-[var(--text-muted)]">{item.typeLabel}</span><Badge fixedWidth="lg" variant={statusVariants[item.status]}>{statusLabels[item.status]}</Badge><PriorityLabel priority={item.priority} /></div>
            <h3 className="mt-1 break-words text-sm font-semibold leading-5 text-[var(--text-primary)]">{item.title}</h3>
            <p className="mt-1 break-words text-xs text-[var(--text-muted)]">{item.client} · {item.matter}</p>
          </div>
        </div>
        <p className="mt-2 line-clamp-1 text-xs text-[var(--text-secondary)]"><span className="font-medium">Why:</span> {item.reason}</p>
        <p className="mt-1 line-clamp-1 text-xs text-[var(--text-muted)]"><span className="font-medium">Impact:</span> {item.impact}</p>
        <div className="mt-2 flex min-w-0 items-center gap-2 text-[11px] text-[var(--text-muted)]"><span className="min-w-0 flex-1 truncate">{item.owner ?? 'Unassigned'} · {item.age} · {item.evidenceAvailability} · {item.decision.label}</span><ChevronRight className="size-4 shrink-0" aria-hidden="true" /></div>
    </button>
  )
}

function DesktopQueueTable({ items, selectedId, onSelect }: { items: ReviewItem[]; selectedId: string | null; onSelect: (item: ReviewItem) => void }) {
  return (
    <Table>
      <TableCaption className="sr-only">Review items with reason, impact, ownership, age, evidence, and primary decision.</TableCaption>
      <TableHeader className="sticky top-0 z-10 bg-[var(--surface)]">
        <TableRow><TableHead className="w-[28%]">Review item</TableHead><TableHead className="w-[34%]">Why / impact</TableHead><TableHead className="w-[18%]">Owner / age</TableHead><TableHead className="w-[20%]">Evidence / decision</TableHead></TableRow>
      </TableHeader>
      <TableBody>
        {items.map((item) => {
          const Icon = typeIcons[item.type]
          return (
            <TableRow key={item.id} data-state={selectedId === item.id ? 'selected' : undefined} tabIndex={0} className="h-[76px] cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent)]" onClick={() => onSelect(item)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(item) } }}>
              <TableCell className="px-3 py-2"><div className="flex min-w-0 items-start gap-2"><span className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--bg-overlay)]"><Icon className="size-3.5" aria-hidden="true" /></span><div className="min-w-0"><div className="flex items-center gap-1.5"><Badge fixedWidth="lg" variant={statusVariants[item.status]}>{statusLabels[item.status]}</Badge><PriorityLabel priority={item.priority} /></div><p className="mt-1 truncate text-xs font-semibold text-[var(--text-primary)]">{item.title}</p><p className="truncate text-[11px] text-[var(--text-muted)]">{item.client} · {item.matter}</p></div></div></TableCell>
              <TableCell className="px-3 py-2"><p className="line-clamp-1 text-xs text-[var(--text-secondary)]"><span className="font-medium text-[var(--text-primary)]">Why:</span> {item.reason}</p><p className="mt-1 line-clamp-1 text-xs text-[var(--text-muted)]"><span className="font-medium">Impact:</span> {item.impact}</p></TableCell>
              <TableCell className="px-3 py-2"><p className="truncate text-xs font-medium">{item.owner ?? 'Unassigned'}</p><p className="mt-1 text-[11px] text-[var(--text-muted)]">{item.age} · {item.typeLabel}</p></TableCell>
              <TableCell className="px-3 py-2"><p className="text-xs">{item.evidenceAvailability} · {item.evidence.length}</p><p className="mt-1 line-clamp-1 text-[11px] text-[var(--text-muted)]">{item.decision.label}</p></TableCell>
            </TableRow>
          )
        })}
      </TableBody>
    </Table>
  )
}

function QueueLoading() {
  return <div aria-busy="true"><p className="sr-only">Loading Review queue fixtures…</p>{[0, 1, 2].map((key) => <div key={key} className="border-b border-[var(--border-subtle)] p-4" aria-hidden="true"><div className="flex gap-3"><Skeleton className="size-8 shrink-0" /><div className="min-w-0 flex-1 space-y-2"><Skeleton className="h-4 w-32" /><Skeleton className="h-5 w-4/5" /><Skeleton className="h-4 w-2/3" /></div></div><div className="mt-4 grid grid-cols-2 gap-3"><Skeleton className="h-12 w-full" /><Skeleton className="h-12 w-full" /><Skeleton className="h-12 w-full" /><Skeleton className="h-12 w-full" /></div></div>)}</div>
}

function StatePanel({ kind, onRetry }: { kind: 'empty' | 'error' | 'filtered'; onRetry?: () => void }) {
  const error = kind === 'error'
  const Icon = error ? AlertCircle : FileQuestion
  return (
    <div className="flex min-h-72 flex-col items-center justify-center p-6 text-center" role={error ? 'alert' : 'status'}>
      <span className={cn('flex size-10 items-center justify-center rounded-[var(--radius-sm)] border', error ? 'border-[var(--danger)] bg-[var(--danger-muted)] text-[var(--danger)]' : 'border-[var(--border)] bg-[var(--bg-overlay)] text-[var(--text-muted)]')}><Icon className="size-5" aria-hidden="true" /></span>
      <h2 className="mt-4 text-sm font-semibold">{error ? 'Review queue could not be displayed' : kind === 'filtered' ? 'No Review items match these filters' : 'No Review decisions are waiting'}</h2>
      <p className="mt-1 max-w-sm text-xs leading-5 text-[var(--text-muted)]">{error ? 'This is the fixture error state. No live data request was attempted.' : kind === 'filtered' ? 'Change a queue filter or clear the search to restore fixture items.' : 'Resolved and superseded items remain available through lifecycle filters when policy permits.'}</p>
      {error && <Button variant="outline" className="mt-4" onClick={onRetry}><RefreshCw className="size-4" aria-hidden="true" />Reload fixture</Button>}
    </div>
  )
}

function QueueBody({ state, items, selectedId, onSelect, onRetry, desktop = false }: { state: PreviewState; items: ReviewItem[]; selectedId: string | null; onSelect: (item: ReviewItem) => void; onRetry: () => void; desktop?: boolean }) {
  if (state === 'loading') return <QueueLoading />
  if (state === 'empty') return <StatePanel kind="empty" />
  if (state === 'error') return <StatePanel kind="error" onRetry={onRetry} />
  if (items.length === 0) return <StatePanel kind="filtered" />
  if (desktop) return <DesktopQueueTable items={items} selectedId={selectedId} onSelect={onSelect} />
  return items.map((item) => <MobileQueueRow key={item.id} item={item} selected={selectedId === item.id} onSelect={() => onSelect(item)} />)
}

function EvidenceCard({ evidence }: { evidence: Evidence }) {
  const variant: 'outline' | 'warning' | 'muted' = evidence.access === 'available' ? 'outline' : evidence.access === 'partial' ? 'warning' : 'muted'
  return (
    <article className="min-w-0 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface)] p-3">
      <div className="flex min-w-0 flex-wrap items-start justify-between gap-2">
        <div className="min-w-0"><p className="break-words text-xs font-semibold text-[var(--text-primary)]">{evidence.label}</p><p className="mt-0.5 break-words font-mono text-[11px] text-[var(--text-muted)]">{evidence.locator}</p></div>
        <Badge variant={variant}>{evidence.access === 'available' ? 'Available' : evidence.access === 'partial' ? 'Partial' : 'Stale'}</Badge>
      </div>
      <p className="mt-3 break-words border-l-2 border-[var(--border-strong)] pl-3 text-sm leading-6 text-[var(--text-secondary)]">{evidence.excerpt}</p>
      <p className="mt-2 text-[11px] text-[var(--text-muted)]">{evidenceKindLabels[evidence.kind]}</p>
    </article>
  )
}

function DecisionPanel({ item, role, selectedOption, onSelectOption }: { item: ReviewItem; role: Role; selectedOption: string; onSelectOption: (id: string) => void }) {
  const superseded = item.status === 'superseded'
  const readOnly = role === 'viewer'
  const authorityRequired = !item.associateCanResolve && role !== 'owner_admin'
  const optionsDisabled = superseded || readOnly || authorityRequired
  const disabledReason = superseded
    ? 'This item is superseded. Its historical evidence is read-only and no outdated decision can be applied.'
    : readOnly
      ? 'Viewer access is read-only. Viewers cannot be assigned actionable Review or record decisions.'
      : authorityRequired
        ? 'This financial decision requires Owner/Admin authority. The Associate may inspect evidence but cannot resolve it.'
        : role === 'owner_admin' && !item.associateCanResolve
          ? 'Owner/Admin authority is active. Select an option to inspect the confirmation step; recording remains disabled in this fixture.'
          : 'Select an option to inspect the confirmation step; recording remains disabled in this fixture.'

  return (
    <section aria-labelledby="decision-heading" className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
      <div className="border-b border-[var(--border-subtle)] p-4"><p className="text-[11px] font-medium uppercase tracking-wide text-[var(--text-muted)]">Typed resolver · {item.decision.kind.replaceAll('_', ' ')}</p><h3 id="decision-heading" className="mt-1 text-sm font-semibold">{item.decision.label}</h3><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">{item.decision.instruction}</p></div>
      {item.decision.options.length > 0 && <fieldset className="space-y-2 p-4 pt-2" disabled={optionsDisabled}><legend className="px-1 text-[11px] font-medium uppercase tracking-wide text-[var(--text-muted)]">Decision options</legend>{item.decision.options.map((option) => <label key={option.id} className={cn('flex min-h-11 items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] p-3 transition-colors', !optionsDisabled && 'cursor-pointer hover:bg-[var(--surface-hover)]', selectedOption === option.id && 'border-[var(--accent)] bg-[var(--accent-muted)]', optionsDisabled && 'opacity-70')}><input type="radio" name={`decision-${item.id}`} value={option.id} checked={selectedOption === option.id} onChange={() => onSelectOption(option.id)} className="mt-0.5 size-4 accent-[var(--accent)]" /><span className="min-w-0"><span className="block break-words text-xs font-medium text-[var(--text-primary)]">{option.label}</span><span className="mt-1 block break-words text-xs leading-5 text-[var(--text-muted)]">{option.explanation}</span></span></label>)}</fieldset>}
      <div className={cn('border-t p-3', superseded ? 'border-[var(--warning)] bg-[var(--warning-muted)]' : 'border-[var(--border-subtle)] bg-[var(--bg-overlay)]')}>
        <p className="flex items-start gap-2 text-xs leading-5 text-[var(--text-secondary)]"><LockKeyhole className="mt-0.5 size-4 shrink-0" aria-hidden="true" />{disabledReason}</p>
      </div>
    </section>
  )
}

function DetailContent({ item, role, selectedOption, onSelectOption, onPreviewSource }: { item: ReviewItem; role: Role; selectedOption: string; onSelectOption: (id: string) => void; onPreviewSource: () => void }) {
  return (
    <div className="space-y-4 p-3 lg:p-4">
      {item.status === 'superseded' && <section role="status" className="rounded-[var(--radius-md)] border border-[var(--warning)] bg-[var(--warning-muted)] p-4"><div className="flex items-start gap-3"><RefreshCw className="mt-0.5 size-5 shrink-0 text-[var(--warning)]" aria-hidden="true" /><div><h3 className="text-sm font-semibold">Source changed · decision superseded</h3><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">Revision {item.revision} cannot resolve the current source. {item.replacementId ? `Replacement fixture ${item.replacementId} owns the current conflict.` : 'Refresh current evidence before deciding.'}</p></div></div></section>}
      <section aria-labelledby="context-heading" className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4"><div className="flex flex-wrap items-start justify-between gap-3"><div><h3 id="context-heading" className="text-sm font-semibold">Decision boundary</h3><p className="mt-1 text-xs text-[var(--text-muted)]">One Review item, one typed resolver, one source revision.</p></div><Button variant="outline" size="sm" onClick={onPreviewSource}><FileSearch className="size-4" aria-hidden="true" />Preview exact source</Button></div><dl className="mt-4 grid gap-x-5 gap-y-3 sm:grid-cols-2"><Fact label="Reason" wide>{item.reason}</Fact><Fact label="Impact" wide>{item.impact}</Fact><Fact label="Client">{item.client}</Fact><Fact label="Matter">{item.matter}</Fact><Fact label="Document">{item.document}</Fact><Fact label="Source authority">{item.sourceVersion} · Review revision {item.revision}</Fact></dl></section>
      <section aria-labelledby="evidence-heading"><div className="flex flex-wrap items-end justify-between gap-2"><div><h3 id="evidence-heading" className="text-sm font-semibold">Evidence first</h3><p className="mt-1 text-xs text-[var(--text-muted)]">Review the typed source facts before choosing a decision.</p></div><Badge variant={item.evidenceAvailability === 'Complete' ? 'outline' : item.evidenceAvailability === 'Partial' ? 'warning' : 'muted'}>{item.evidenceAvailability} · {item.evidence.length}</Badge></div><div className="mt-3 space-y-2">{item.evidence.map((evidence) => <EvidenceCard key={evidence.id} evidence={evidence} />)}</div></section>
      <DecisionPanel item={item} role={role} selectedOption={selectedOption} onSelectOption={onSelectOption} />
    </div>
  )
}

function DetailHeader({ item, mobile, onBack, onClose }: { item: ReviewItem; mobile?: boolean; onBack?: () => void; onClose?: () => void }) {
  const Icon = typeIcons[item.type]
  return (
    <div className="shrink-0 border-b border-[var(--border)] bg-[var(--surface)] p-3 lg:p-4">
      <div className="flex min-w-0 items-start gap-3">
        {mobile && <Button variant="ghost" size="icon" className="-ml-2 shrink-0" onClick={onBack} aria-label="Back to Review queue"><ArrowLeft className="size-5" aria-hidden="true" /></Button>}
        <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--bg-overlay)] text-[var(--text-secondary)]"><Icon className="size-4" aria-hidden="true" /></span>
        <div className="min-w-0 flex-1"><div className="flex min-w-0 flex-wrap items-center gap-2"><span className="text-xs font-medium text-[var(--text-muted)]">{item.typeLabel}</span><Badge fixedWidth="lg" variant={statusVariants[item.status]}>{statusLabels[item.status]}</Badge><PriorityLabel priority={item.priority} /></div><h2 className="mt-1 break-words text-sm font-semibold leading-5">{item.title}</h2><p className="mt-1 break-words text-xs text-[var(--text-muted)]">Owner: {item.owner ?? 'Unassigned organisation queue'} · Age: {item.age}</p></div>
        {!mobile && <Button variant="ghost" size="icon" className="-mr-2 shrink-0" onClick={onClose} aria-label="Close Review detail"><X className="size-4" aria-hidden="true" /></Button>}
      </div>
    </div>
  )
}

function DecisionFooter({ item, role, selectedOption, onReview }: { item: ReviewItem; role: Role; selectedOption: string; onReview: () => void }) {
  const canResolve = role !== 'viewer' && (item.associateCanResolve || role === 'owner_admin') && item.status !== 'superseded'
  const label = item.status === 'superseded'
    ? 'No decision — superseded'
    : role === 'viewer'
      ? 'Viewer cannot record decisions'
      : !canResolve
        ? 'Owner / Admin decision required'
        : selectedOption
          ? 'Review selected decision'
          : 'Select a decision option'
  return (
    <div className="shrink-0 border-t border-[var(--border)] bg-[var(--surface)] p-3">
      <Button className="w-full" disabled={!canResolve || !selectedOption} onClick={onReview}><Check className="size-4" aria-hidden="true" />{label}</Button>
      <p className="mt-2 text-center text-[11px] text-[var(--text-muted)]">Review is local to this fixture; canonical recording remains unavailable.</p>
    </div>
  )
}

function DecisionReviewDialog({ item, selectedOption, open, onOpenChange }: { item: ReviewItem; selectedOption: string; open: boolean; onOpenChange: (open: boolean) => void }) {
  const option = item.decision.options.find((candidate) => candidate.id === selectedOption)
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent showClose={false} className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Review decision before recording</DialogTitle>
          <DialogDescription>Confirm the selected typed outcome and its source authority. This fixture cannot create a canonical decision.</DialogDescription>
        </DialogHeader>
        <dl className="space-y-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg-overlay)] p-4">
          <Fact label="Decision">{option?.label ?? 'No option selected'}</Fact>
          <Fact label="Evidence basis">{option?.explanation ?? 'Return to the evidence and choose an option.'}</Fact>
          <Fact label="Authority">{item.sourceVersion} · Review revision {item.revision}</Fact>
        </dl>
        <div className="mt-4 rounded-[var(--radius-sm)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3 text-xs leading-5 text-[var(--text-secondary)]">
          Fixture safeguard: the final record action is disabled and no RPC is invoked.
        </div>
        <DialogFooter>
          <DialogClose asChild><Button variant="outline">Return to evidence</Button></DialogClose>
          <Button disabled><Check className="size-4" aria-hidden="true" />Record decision — fixture disabled</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function DesktopDetail({ item, role, state, onClose, onPreviewSource, onRetry }: { item: ReviewItem; role: Role; state: PreviewState; onClose: () => void; onPreviewSource: () => void; onRetry: () => void }) {
  const ready = state === 'default' || state === 'long_content' || state === 'stale'
  const [selectedOption, setSelectedOption] = useState('')
  const [reviewOpen, setReviewOpen] = useState(false)
  return <aside className="flex min-h-0 w-[32rem] shrink-0 flex-col overflow-hidden border-l border-[var(--border)] bg-[var(--bg)]" aria-label={`Review detail for ${item.title}`}><DetailHeader item={item} onClose={onClose} /><div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain" style={{ scrollbarGutter: 'stable' }}>{state === 'loading' ? <div className="space-y-3 p-4" aria-busy="true"><p className="sr-only">Loading Review evidence and decision controls…</p><Skeleton className="h-32 w-full" /><Skeleton className="h-5 w-32" /><Skeleton className="h-28 w-full" /><Skeleton className="h-28 w-full" /><Skeleton className="h-48 w-full" /></div> : state === 'error' ? <StatePanel kind="error" onRetry={onRetry} /> : <DetailContent item={item} role={role} selectedOption={selectedOption} onSelectOption={setSelectedOption} onPreviewSource={onPreviewSource} />}</div>{ready && <DecisionFooter item={item} role={role} selectedOption={selectedOption} onReview={() => setReviewOpen(true)} />}<DecisionReviewDialog item={item} selectedOption={selectedOption} open={reviewOpen} onOpenChange={setReviewOpen} /></aside>
}

function AboutDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent showClose={false} className="sm:max-w-md"><DialogHeader><DialogTitle>Fixture-only Review concept</DialogTitle><DialogDescription>This page uses local deterministic fixtures to evaluate queue density, evidence hierarchy, decision authority, and responsive behavior. It does not read or write Review records, open source files, send notifications, or invoke RPCs.</DialogDescription></DialogHeader><DialogFooter><DialogClose asChild><Button>Close</Button></DialogClose></DialogFooter></DialogContent></Dialog>
}

function MobileDetail({ item, role, onBack, onPreviewSource }: { item: ReviewItem; role: Role; onBack: () => void; onPreviewSource: () => void }) {
  const [selectedOption, setSelectedOption] = useState('')
  const [reviewOpen, setReviewOpen] = useState(false)
  return <section className="flex h-full min-h-0 min-w-0 flex-col overflow-hidden bg-[var(--bg)]" aria-label={`Review detail for ${item.title}`}><DetailHeader item={item} mobile onBack={onBack} /><div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain" style={{ scrollbarGutter: 'stable' }}><DetailContent item={item} role={role} selectedOption={selectedOption} onSelectOption={setSelectedOption} onPreviewSource={onPreviewSource} /></div><DecisionFooter item={item} role={role} selectedOption={selectedOption} onReview={() => setReviewOpen(true)} /><DecisionReviewDialog item={item} selectedOption={selectedOption} open={reviewOpen} onOpenChange={setReviewOpen} /></section>
}

export function ReviewWorkspaceConcept() {
  const { resolvedTheme, setTheme } = useTheme()
  const [themeReady, setThemeReady] = useState(false)
  const dark = themeReady && resolvedTheme === 'dark'
  const [role, setRole] = useState<Role>('associate')
  const [previewState, setPreviewState] = useState<PreviewState>('default')
  const [query, setQuery] = useState('')
  const [scope, setScope] = useState<QueueScope>('all')
  const [typeFilter, setTypeFilter] = useState<TypeFilter>('all')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('active')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [mobileDetail, setMobileDetail] = useState(false)
  const [aboutOpen, setAboutOpen] = useState(false)
  const [announcement, setAnnouncement] = useState('')
  const mobileListRef = useRef<HTMLElement>(null)
  const mobileListPosition = useRef(0)

  useEffect(() => {
    const frame = requestAnimationFrame(() => setThemeReady(true))
    return () => cancelAnimationFrame(frame)
  }, [])

  const visibleItems = useMemo(() => {
    let items = reviewFixtures
    if (previewState === 'long_content') items = items.filter((item) => item.longContent)
    else if (previewState === 'stale') items = items.filter((item) => item.status === 'superseded')
    else items = items.filter((item) => !item.longContent)

    const normalizedQuery = query.trim().toLowerCase()
    return items.filter((item) => {
      if (normalizedQuery && ![item.title, item.reason, item.impact, item.client, item.matter, item.document, item.owner ?? 'unassigned'].some((value) => value.toLowerCase().includes(normalizedQuery))) return false
      if (scope === 'mine' && item.owner !== 'Rishikesh Joshi') return false
      if (scope === 'unassigned' && item.owner !== null) return false
      if (typeFilter !== 'all' && item.type !== typeFilter) return false
      if (statusFilter === 'active' && item.status === 'superseded') return false
      if (statusFilter !== 'active' && statusFilter !== 'all' && item.status !== statusFilter) return false
      return true
    })
  }, [previewState, query, scope, statusFilter, typeFilter])

  const selectedItem = visibleItems.find((item) => item.id === selectedId) ?? null

  function selectItem(item: ReviewItem, mobile: boolean) {
    if (mobile) {
      mobileListPosition.current = mobileListRef.current?.scrollTop ?? 0
      setMobileDetail(true)
    }
    setSelectedId(item.id)
  }

  function backToQueue() {
    setMobileDetail(false)
    requestAnimationFrame(() => {
      if (mobileListRef.current) mobileListRef.current.scrollTop = mobileListPosition.current
    })
  }

  function changePreview(state: PreviewState) {
    setPreviewState(state)
    setMobileDetail(false)
    setSelectedId(null)
    if (state === 'stale') setStatusFilter('all')
    if (state === 'default') setStatusFilter('active')
  }

  const stateCount = previewState === 'loading' || previewState === 'empty' || previewState === 'error' ? 0 : visibleItems.length

  return (
    <div className="flex h-dvh min-w-0 flex-col overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]">
      <div className="flex min-h-0 min-w-0 flex-1 overflow-hidden">
        <ConceptRail />
        <main className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden">
          <WorkspaceHeader state={previewState} role={role} dark={dark} onState={changePreview} onRole={setRole} onDark={() => setTheme(dark ? 'light' : 'dark')} onAbout={() => setAboutOpen(true)} />
          <div className={cn('flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden', mobileDetail && 'max-xl:hidden')}>
            <QueueWorkbar query={query} scope={scope} type={typeFilter} status={statusFilter} count={stateCount} onQuery={setQuery} onScope={setScope} onType={setTypeFilter} onStatus={setStatusFilter} />
            <div className="hidden min-h-0 min-w-0 flex-1 overflow-hidden xl:flex">
              <section aria-label="Review queue" className="custom-scrollbar min-h-0 min-w-0 flex-1 overflow-y-auto overscroll-contain bg-[var(--surface)]" style={{ scrollbarGutter: 'stable' }}><QueueBody desktop state={previewState} items={visibleItems} selectedId={selectedItem?.id ?? null} onSelect={(item) => selectItem(item, false)} onRetry={() => changePreview('default')} /></section>
              {selectedItem && previewState !== 'empty' && <DesktopDetail key={selectedItem.id} item={selectedItem} role={role} state={previewState} onClose={() => setSelectedId(null)} onPreviewSource={() => setAnnouncement('Fixture only: no canonical document, Matter, or signed asset was opened.')} onRetry={() => changePreview('default')} />}
            </div>
            <section ref={mobileListRef} aria-label="Review queue" className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain bg-[var(--surface)] xl:hidden" style={{ scrollbarGutter: 'stable' }}><QueueBody state={previewState} items={visibleItems} selectedId={selectedItem?.id ?? null} onSelect={(item) => selectItem(item, true)} onRetry={() => changePreview('default')} /></section>
          </div>
          <div className={cn('hidden min-h-0 flex-1 xl:hidden', mobileDetail && 'flex')}>
            {selectedItem && <MobileDetail key={selectedItem.id} item={selectedItem} role={role} onBack={backToQueue} onPreviewSource={() => setAnnouncement('Fixture only: no canonical document, Matter, or signed asset was opened.')} />}
          </div>
        </main>
      </div>
      <AboutDialog open={aboutOpen} onOpenChange={setAboutOpen} />
      <div className="sr-only" aria-live="polite">{announcement}</div>
    </div>
  )
}
