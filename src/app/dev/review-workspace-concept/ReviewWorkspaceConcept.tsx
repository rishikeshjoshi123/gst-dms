'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import { useTheme } from 'next-themes'
import {
  AlertCircle,
  ArrowLeft,
  CalendarClock,
  Check,
  CircleCheck,
  ChevronDown,
  ChevronLeft,
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
  RotateCw,
  X,
  ZoomIn,
  ZoomOut,
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
type ReviewStatus = 'needs_review' | 'closed'
type Priority = 'normal' | 'high' | 'urgent'
type TypeFilter = 'all' | ReviewType
type PriorityFilter = 'all' | Priority
type StatusFilter = 'needs_review' | 'closed' | 'all'
type EvidenceAccess = 'available' | 'partial' | 'stale'
type EvidenceKind = 'source_quote' | 'document_fact' | 'comparison' | 'matter_context'
type DetailTab = 'evidence' | 'decision'
type SourceContext = { page: number; label: string | null }

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
  confirmationEffects?: string[]
  confirmLabel?: string
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
  evidenceAvailability: 'Complete' | 'Partial' | 'Stale'
  status: ReviewStatus
  priority: Priority
  priorityReason: string
  client: string
  matter: string
  document: string
  sourceVersion: string
  revision: number
  evidence: Evidence[]
  decision: TypedDecision
  associateCanResolve: boolean
  closureReason?: 'decision_recorded' | 'dismissed' | 'source_replaced'
  recordedDecision?: { outcome: string; reason?: string }
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
    evidenceAvailability: 'Complete',
    status: 'needs_review',
    priority: 'high',
    priorityReason: 'The conflicting total blocks the appeal working-paper calculation, but no deadline within 72 hours is attached.',
    client: 'Apex Auto Components Private Limited',
    matter: 'FY 2023–24 ITC mismatch appeal',
    document: 'Supplier invoice reconciliation — signed.pdf',
    sourceVersion: 'Document version 8',
    revision: 4,
    evidence: [
      { id: 'ext-quote-1', kind: 'source_quote', label: 'Signed annexure · page 14', locator: 'Page 14 · table total', excerpt: 'Taxable value total: ₹18,42,780.00', access: 'available' },
      { id: 'ext-quote-2', kind: 'source_quote', label: 'Invoice summary · page 2', locator: 'Page 2 · summary block', excerpt: 'Aggregate taxable value: ₹18,24,780.00', access: 'available' },
      { id: 'ext-compare', kind: 'comparison', label: 'Difference between the two totals', locator: 'Calculated from the two values above', excerpt: '₹18,000.00 difference. Both totals appear in the document.', access: 'available' },
    ],
    decision: {
      kind: 'select_extracted_value',
      label: 'Choose invoice total',
      instruction: 'Choose the value that the effective invoice metadata should use. The evidence remains attached to the recorded decision.',
      options: [
        { id: 'annexure-total', label: 'Use ₹18,42,780.00', explanation: 'Supported by the signed annexure on page 14.' },
        { id: 'summary-total', label: 'Use ₹18,24,780.00', explanation: 'Supported by the invoice summary on page 2.' },
        {
          id: 'return-source',
          label: 'Neither value is reliable',
          explanation: 'Keep the invoice total unchanged and flag this active Review item for source clarification.',
          confirmationEffects: [
            'The effective invoice total remains unchanged.',
            'This item stays in the active Review queue with a “Source clarification required” flag.',
            'The clarification request, evidence references, and review reason remain attached to this item.',
          ],
          confirmLabel: 'Request clarification',
        },
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
    evidenceAvailability: 'Complete',
    status: 'needs_review',
    priority: 'high',
    priorityReason: 'The document cannot complete intake placement or downstream processing until this decision is made.',
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
      instruction: 'Choose the Matter this document belongs to. If neither match is safe, return it to intake for more evidence.',
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
    evidenceAvailability: 'Partial',
    status: 'needs_review',
    priority: 'normal',
    priorityReason: 'The possible relationship does not currently block a filing, deadline, or required processing step.',
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
    evidenceAvailability: 'Complete',
    status: 'needs_review',
    priority: 'urgent',
    priorityReason: 'A candidate filing deadline has passed and must be verified before accountable reminders can be trusted.',
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
      instruction: 'Choose the supported date or return the deadline as provisional. The recorded outcome will retain the calculation rule and supporting evidence.',
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
    evidenceAvailability: 'Complete',
    status: 'needs_review',
    priority: 'high',
    priorityReason: 'The decision materially changes the Matter financial summary and requires privileged authority.',
    client: 'Western Freight Services',
    matter: 'E-way bill penalty response',
    document: 'Demand order and computation sheet.pdf',
    sourceVersion: 'Document version 4',
    revision: 6,
    evidence: [
      { id: 'finance-order', kind: 'source_quote', label: 'Demand order', locator: 'Page 17 · demand table', excerpt: 'Tax ₹8,60,000 · Interest ₹1,24,600 · Total ₹9,84,600', access: 'available' },
      { id: 'finance-sheet', kind: 'source_quote', label: 'Signed computation', locator: 'Page 21 · signed schedule', excerpt: 'Tax ₹8,42,000 · Interest ₹1,42,600 · Total ₹9,84,600', access: 'available' },
      { id: 'finance-compare', kind: 'comparison', label: 'Difference in allocation', locator: 'Calculated from the two values above', excerpt: 'The total agrees; ₹18,000 is allocated to different components.', access: 'available' },
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
    id: 'review-resolved-063',
    type: 'extraction_conflict',
    typeLabel: 'Extraction conflict',
    title: 'Resolve taxable turnover from signed reconciliation',
    reason: 'The return summary and signed reconciliation contained different taxable turnover values.',
    impact: 'The selected value updated the effective turnover used by the Matter summary.',
    age: '9 days',
    evidenceAvailability: 'Complete',
    status: 'closed',
    priority: 'normal',
    priorityReason: 'This item is closed; its former priority is retained only as record context.',
    client: 'Apex Auto Components Private Limited',
    matter: 'FY 2022–23 annual return reconciliation',
    document: 'Signed annual reconciliation.pdf',
    sourceVersion: 'Document version 5',
    revision: 3,
    evidence: [
      { id: 'resolved-reconciliation', kind: 'source_quote', label: 'Signed reconciliation · page 8', locator: 'Page 8 · final total', excerpt: 'Verified taxable turnover: ₹4,82,16,400.00', access: 'available' },
      { id: 'resolved-summary', kind: 'source_quote', label: 'Return summary · page 2', locator: 'Page 2 · turnover summary', excerpt: 'Reported taxable turnover: ₹4,80,16,400.00', access: 'available' },
    ],
    decision: {
      kind: 'select_extracted_value',
      label: 'Recorded invoice total',
      instruction: 'This decision is complete and read-only. Review its evidence and recorded outcome below.',
      options: [
        { id: 'signed-turnover', label: 'Use ₹4,82,16,400.00', explanation: 'Supported by the signed reconciliation on page 8.' },
        { id: 'summary-turnover', label: 'Use ₹4,80,16,400.00', explanation: 'Supported by the return summary on page 2.' },
      ],
    },
    associateCanResolve: true,
    closureReason: 'decision_recorded',
    recordedDecision: { outcome: 'Used ₹4,82,16,400.00 from the signed reconciliation.' },
  },
  {
    id: 'review-dismissed-041',
    type: 'relationship_conflict',
    typeLabel: 'Relationship conflict',
    title: 'Possible duplicate notice relationship',
    reason: 'A notice reference resembled an existing record but the proceeding identifiers did not agree.',
    impact: 'No document relationship was created.',
    age: '12 days',
    evidenceAvailability: 'Complete',
    status: 'closed',
    priority: 'normal',
    priorityReason: 'This item is closed; its former priority is retained only as record context.',
    client: 'Mehta Industrial Works',
    matter: 'DRC-01 reply and hearing',
    document: 'Departmental notice clarification.pdf',
    sourceVersion: 'Document version 2',
    revision: 2,
    evidence: [
      { id: 'dismissed-reference', kind: 'source_quote', label: 'Notice reference · page 1', locator: 'Page 1 · reference block', excerpt: 'Proceeding reference did not match the candidate notice.', access: 'available' },
    ],
    decision: {
      kind: 'confirm_document_relationship',
      label: 'Recorded relationship decision',
      instruction: 'This Review item was dismissed with a recorded reason and is read-only.',
      options: [
        { id: 'no-relationship', label: 'No supported relationship', explanation: 'Leave the documents unlinked.' },
      ],
    },
    associateCanResolve: true,
    closureReason: 'dismissed',
    recordedDecision: { outcome: 'No relationship was created.', reason: 'The proceeding identifiers refer to different matters.' },
  },
  {
    id: 'review-old-019',
    type: 'extraction_conflict',
    typeLabel: 'Extraction conflict',
    title: 'Closed automatically after source replacement',
    reason: 'A corrected source version was uploaded after this evidence snapshot was created.',
    impact: 'No decision can apply to the current document; the replacement item owns any remaining conflict.',
    age: '6 days',
    evidenceAvailability: 'Stale',
    status: 'closed',
    priority: 'normal',
    priorityReason: 'This item is closed automatically because its source was replaced.',
    client: 'Apex Auto Components Private Limited',
    matter: 'FY 2023–24 ITC mismatch appeal',
    document: 'Supplier declaration — previous version.pdf',
    sourceVersion: 'Document version 3 · no longer current',
    revision: 5,
    evidence: [
      { id: 'old-gstin', kind: 'source_quote', label: 'Previous-version quotation', locator: 'Version 3 · page 1', excerpt: 'GSTIN: 27AAECA1842M1Z7', access: 'stale' },
      { id: 'new-gstin', kind: 'document_fact', label: 'Current source fact', locator: 'Version 4 · page 1', excerpt: 'Corrected source version is current. Evidence refresh is required before any decision.', access: 'available' },
    ],
    decision: {
      kind: 'select_extracted_value',
      label: 'No decision — source replaced',
      instruction: 'This historical evidence is read-only. A current replacement item must be opened instead of applying an outdated choice.',
      options: [],
    },
    associateCanResolve: false,
    closureReason: 'source_replaced',
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
    evidenceAvailability: 'Partial',
    status: 'needs_review',
    priority: 'high',
    priorityReason: 'The bundle cannot complete canonical placement or downstream processing until it is separated or assigned.',
    client: 'Shree Venkateshwara Precision Components and Renewable Energy Systems Private Limited',
    matter: 'Consolidated FY 2024–25 proceedings, supplier-confirmation reconciliation, transport evidence, and appeal preparation',
    document: 'Consolidated reply with annexures, schedules, reconciliations, signed authority, and supporting evidence — final reviewed bundle.pdf',
    sourceVersion: 'Staged source version 11',
    revision: 9,
    evidence: [
      { id: 'long-cover', kind: 'source_quote', label: 'Amended covering letter with a deliberately long evidence label that must wrap naturally', locator: 'Page 1 · paragraphs 2–5', excerpt: 'The reply consolidates the classification proceeding, transport-penalty response, and supplier-confirmation reconciliation while preserving their separate notice references and reporting periods.', access: 'available' },
      { id: 'long-annexures', kind: 'comparison', label: 'Three candidate Matter lineages', locator: 'Placement comparison · revision 9', excerpt: 'Candidate A matches the classification notice, candidate B matches the transport schedule, and candidate C matches the reporting period. The signed authority names the client but does not identify one proceeding.', access: 'partial' },
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
  needs_review: 'Needs review',
  closed: 'Closed',
}

const statusVariants: Record<ReviewStatus, 'warning' | 'muted'> = {
  needs_review: 'warning',
  closed: 'muted',
}

const typeIcons: Record<ReviewType, typeof FileSearch> = {
  extraction_conflict: FileSearch,
  ambiguous_placement: FolderInput,
  relationship_conflict: GitCompareArrows,
  deadline_verification: CalendarClock,
  financial_verification: CircleDollarSign,
}

const evidenceKindLabels: Record<EvidenceKind, string> = {
  source_quote: 'Citation',
  document_fact: 'Supporting document record',
  comparison: 'Calculated comparison',
  matter_context: 'Supporting Matter record',
}

const previewLabels: Record<PreviewState, string> = {
  default: 'Default queue',
  loading: 'Loading',
  empty: 'Empty',
  error: 'Error',
  long_content: 'Long content',
  stale: 'Source replaced',
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

function ColumnFilterMenu<T extends string>({ label, value, defaultValue, options, onChange }: { label: string; value: T; defaultValue: T; options: Array<{ value: T; label: string }>; onChange: (value: T) => void }) {
  const current = options.find((option) => option.value === value)?.label ?? label
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button type="button" className="flex min-h-8 items-center gap-1.5 rounded-[var(--radius-sm)] px-1.5 text-xs font-medium text-[var(--text-muted)] outline-none hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)] focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">
          <Filter className="size-3.5" aria-hidden="true" /><span>{label}</span>{value !== defaultValue && <span className="size-1.5 rounded-[var(--radius-full)] bg-[var(--primary)]" aria-label={`Filtered by ${current}`} />}<ChevronDown className="size-3.5" aria-hidden="true" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start">
        <DropdownMenuLabel>{label}</DropdownMenuLabel><DropdownMenuSeparator />
        <DropdownMenuRadioGroup value={value} onValueChange={(next) => onChange(next as T)}>{options.map((option) => <DropdownMenuRadioItem key={option.value} value={option.value}>{option.label}</DropdownMenuRadioItem>)}</DropdownMenuRadioGroup>
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
        <p className="truncate text-xs text-[var(--text-muted)]">Human decisions supported by clear source evidence</p>
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

function QueueWorkbar({ query, type, priority, status, count, onQuery, onType, onPriority, onStatus }: { query: string; type: TypeFilter; priority: PriorityFilter; status: StatusFilter; count: number; onQuery: (value: string) => void; onType: (value: TypeFilter) => void; onPriority: (value: PriorityFilter) => void; onStatus: (value: StatusFilter) => void }) {
  return (
    <div className="shrink-0 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 py-2 lg:px-4">
      <div className="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-center">
        <label className="relative min-w-0 flex-1 sm:max-w-sm">
          <span className="sr-only">Search Review queue fixtures</span>
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
          <Input value={query} onChange={(event) => onQuery(event.target.value)} placeholder="Search Review queue" className="pl-9" />
        </label>
        <div className="grid min-w-0 grid-cols-2 gap-2 sm:contents xl:hidden">
          <FilterMenu label="Review type" value={type} onChange={onType} options={[{ value: 'all', label: 'All types' }, { value: 'extraction_conflict', label: 'Extraction' }, { value: 'ambiguous_placement', label: 'Placement' }, { value: 'relationship_conflict', label: 'Relationship' }, { value: 'deadline_verification', label: 'Deadline' }, { value: 'financial_verification', label: 'Financial' }]} />
          <FilterMenu label="Priority" value={priority} onChange={onPriority} options={[{ value: 'all', label: 'All priorities' }, { value: 'urgent', label: 'Urgent · due or overdue within 72 hours' }, { value: 'high', label: 'High · blocking or material impact' }, { value: 'normal', label: 'Normal · standard review' }]} />
          <FilterMenu label="Status" value={status} onChange={onStatus} options={[{ value: 'needs_review', label: 'Needs review' }, { value: 'closed', label: 'Closed' }, { value: 'all', label: 'All items' }]} />
        </div>
        <p className="shrink-0 text-xs text-[var(--text-muted)] sm:ml-auto" aria-live="polite">{count} {count === 1 ? 'item' : 'items'}</p>
      </div>
    </div>
  )
}

function PriorityLabel({ priority, reason, labelled = false }: { priority: Priority; reason: string; labelled?: boolean }) {
  return <span title={reason} aria-label={`${priority} priority: ${reason}`} className={cn('text-xs font-medium capitalize', priority === 'urgent' && 'text-[var(--danger)]', priority === 'high' && 'text-[var(--warning)]', priority === 'normal' && 'text-[var(--text-muted)]')}>{labelled && 'Priority: '}{priority}</span>
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
            <div className="flex min-w-0 flex-wrap items-center gap-2"><Badge fixedWidth="lg" variant={statusVariants[item.status]}>{statusLabels[item.status]}</Badge><PriorityLabel priority={item.priority} reason={item.priorityReason} labelled /></div>
            <h3 className="mt-1 break-words text-sm font-semibold leading-5 text-[var(--text-primary)]">{item.title}</h3>
            <p className="mt-1 line-clamp-1 text-xs text-[var(--text-muted)]">{item.matter}</p>
          </div>
        </div>
        <div className="mt-2 flex min-w-0 items-center gap-2 text-xs text-[var(--text-muted)]"><span className="min-w-0 flex-1 truncate">{item.typeLabel} · {item.age}</span><ChevronRight className="size-4 shrink-0" aria-hidden="true" /></div>
    </button>
  )
}

function DesktopQueueTable({ items, selectedId, type, priority, status, onType, onPriority, onStatus, onSelect }: { items: ReviewItem[]; selectedId: string | null; type: TypeFilter; priority: PriorityFilter; status: StatusFilter; onType: (value: TypeFilter) => void; onPriority: (value: PriorityFilter) => void; onStatus: (value: StatusFilter) => void; onSelect: (item: ReviewItem) => void }) {
  return (
    <Table className="table-fixed">
      <TableCaption>Review queue. Select an item to inspect its reason, impact, evidence, and decision.</TableCaption>
      <colgroup><col className="w-[46%]" /><col className="w-[18%]" /><col className="w-[12%]" /><col className="w-[10%]" /><col className="w-[14%]" /></colgroup>
      <TableHeader sticky>
        <TableRow><TableHead>Review item</TableHead><TableHead><ColumnFilterMenu label="Type" value={type} defaultValue="all" onChange={onType} options={[{ value: 'all', label: 'All types' }, { value: 'extraction_conflict', label: 'Extraction' }, { value: 'ambiguous_placement', label: 'Placement' }, { value: 'relationship_conflict', label: 'Relationship' }, { value: 'deadline_verification', label: 'Deadline' }, { value: 'financial_verification', label: 'Financial' }]} /></TableHead><TableHead><ColumnFilterMenu label="Priority" value={priority} defaultValue="all" onChange={onPriority} options={[{ value: 'all', label: 'All priorities' }, { value: 'urgent', label: 'Urgent · due or overdue within 72 hours' }, { value: 'high', label: 'High · blocking or material impact' }, { value: 'normal', label: 'Normal · standard review' }]} /></TableHead><TableHead>Age</TableHead><TableHead><ColumnFilterMenu label="Status" value={status} defaultValue="needs_review" onChange={onStatus} options={[{ value: 'needs_review', label: 'Needs review' }, { value: 'closed', label: 'Closed' }, { value: 'all', label: 'All items' }]} /></TableHead></TableRow>
      </TableHeader>
      <TableBody>
        {items.map((item) => {
          const Icon = typeIcons[item.type]
          return (
            <TableRow key={item.id} interactive selected={selectedId === item.id} tabIndex={0} aria-label={`View Review details for ${item.title}`} className="cursor-pointer outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]" onClick={() => onSelect(item)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(item) } }}>
              <TableCell className="py-1.5"><div className="flex min-h-11 min-w-0 items-center gap-3"><span className="flex size-8 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--accent)]"><Icon className="size-4" aria-hidden="true" /></span><span className="min-w-0"><span className="block truncate font-medium text-[var(--text-primary)]">{item.title}</span><span className="mt-0.5 block truncate text-xs text-[var(--text-muted)]">{item.client} · {item.matter}</span></span></div></TableCell>
              <TableCell className="py-1.5 truncate text-xs text-[var(--text-secondary)]">{item.typeLabel}</TableCell>
              <TableCell className="py-1.5"><PriorityLabel priority={item.priority} reason={item.priorityReason} /></TableCell>
              <TableCell className="py-1.5 whitespace-nowrap text-xs text-[var(--text-secondary)]">{item.age}</TableCell>
              <TableCell className="py-1.5"><Badge fixedWidth="lg" variant={statusVariants[item.status]}>{statusLabels[item.status]}</Badge></TableCell>
            </TableRow>
          )
        })}
      </TableBody>
    </Table>
  )
}

function QueueLoading({ desktop }: { desktop: boolean }) {
  if (!desktop) return <div aria-busy="true"><p className="sr-only">Loading Review queue fixtures…</p>{[0, 1, 2, 3].map((key) => <div key={key} className="min-h-[88px] border-b border-[var(--border-subtle)] p-3" aria-hidden="true"><div className="flex gap-3"><Skeleton className="size-8 shrink-0" /><div className="min-w-0 flex-1 space-y-2"><Skeleton className="h-4 w-32" /><Skeleton className="h-4 w-4/5" /><Skeleton className="h-3 w-2/3" /></div></div></div>)}</div>
  return <div aria-busy="true"><p className="sr-only">Loading Review queue fixtures…</p><Table className="table-fixed"><TableCaption>Loading Review items.</TableCaption><colgroup><col className="w-[46%]" /><col className="w-[18%]" /><col className="w-[12%]" /><col className="w-[10%]" /><col className="w-[14%]" /></colgroup><TableHeader sticky><TableRow><TableHead>Review item</TableHead><TableHead>Type</TableHead><TableHead>Priority</TableHead><TableHead>Age</TableHead><TableHead>Status</TableHead></TableRow></TableHeader><TableBody>{[0, 1, 2, 3, 4].map((key) => <TableRow key={key} aria-hidden="true"><TableCell className="py-1.5"><div className="flex min-h-11 items-center gap-3"><Skeleton className="size-8 shrink-0" /><div className="min-w-0 flex-1"><Skeleton className="h-3.5 w-4/5" /><Skeleton className="mt-2 h-3 w-3/5" /></div></div></TableCell><TableCell className="py-1.5"><Skeleton className="h-3 w-24" /></TableCell><TableCell className="py-1.5"><Skeleton className="h-3 w-16" /></TableCell><TableCell className="py-1.5"><Skeleton className="h-3 w-14" /></TableCell><TableCell className="py-1.5"><Skeleton className="h-6 w-24" /></TableCell></TableRow>)}</TableBody></Table></div>
}

function StatePanel({ kind, onRetry }: { kind: 'empty' | 'error' | 'filtered'; onRetry?: () => void }) {
  const error = kind === 'error'
  const Icon = error ? AlertCircle : FileQuestion
  return (
    <div className="flex min-h-72 flex-col items-center justify-center p-6 text-center" role={error ? 'alert' : 'status'}>
      <span className={cn('flex size-10 items-center justify-center rounded-[var(--radius-sm)] border', error ? 'border-[var(--danger)] bg-[var(--danger-muted)] text-[var(--danger)]' : 'border-[var(--border)] bg-[var(--bg-overlay)] text-[var(--text-muted)]')}><Icon className="size-5" aria-hidden="true" /></span>
      <h2 className="mt-4 text-sm font-semibold">{error ? 'Review queue could not be displayed' : kind === 'filtered' ? 'No Review items match these filters' : 'No Review decisions are waiting'}</h2>
      <p className="mt-1 max-w-sm text-xs leading-5 text-[var(--text-muted)]">{error ? 'This is the fixture error state. No live data request was attempted.' : kind === 'filtered' ? 'Change a queue filter or clear the search to restore fixture items.' : 'Completed Review items remain available through the Closed status filter.'}</p>
      {error && <Button variant="outline" className="mt-4" onClick={onRetry}><RefreshCw className="size-4" aria-hidden="true" />Reload fixture</Button>}
    </div>
  )
}

function QueueBody({ state, items, selectedId, type, priority, status, onType, onPriority, onStatus, onSelect, onRetry, desktop = false }: { state: PreviewState; items: ReviewItem[]; selectedId: string | null; type: TypeFilter; priority: PriorityFilter; status: StatusFilter; onType: (value: TypeFilter) => void; onPriority: (value: PriorityFilter) => void; onStatus: (value: StatusFilter) => void; onSelect: (item: ReviewItem) => void; onRetry: () => void; desktop?: boolean }) {
  if (state === 'loading') return <QueueLoading desktop={desktop} />
  if (state === 'empty') return <StatePanel kind="empty" />
  if (state === 'error') return <StatePanel kind="error" onRetry={onRetry} />
  if (items.length === 0) return <StatePanel kind="filtered" />
  if (desktop) return <DesktopQueueTable items={items} selectedId={selectedId} type={type} priority={priority} status={status} onType={onType} onPriority={onPriority} onStatus={onStatus} onSelect={onSelect} />
  return items.map((item) => <MobileQueueRow key={item.id} item={item} selected={selectedId === item.id} onSelect={() => onSelect(item)} />)
}

function EvidenceCard({ evidence, position, onOpen }: { evidence: Evidence; position: number; onOpen?: () => void }) {
  const isCitation = evidence.kind === 'source_quote'
  const actionLabel = isCitation ? 'Open citation' : 'Open source'
  const content = (
    <div className="flex min-w-0 items-start gap-3">
      <span className="flex size-7 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] text-xs font-semibold text-[var(--text-secondary)]" aria-hidden="true">{position}</span>
      <div className="min-w-0 flex-1">
        <div className="flex min-w-0 flex-wrap items-start justify-between gap-2">
          <div className="min-w-0">
            <p className="break-words text-sm font-semibold leading-5 text-[var(--text-primary)]">{evidence.label}</p>
            <p className="mt-0.5 break-words text-[11px] text-[var(--text-muted)]"><span className={isCitation ? 'font-medium text-[var(--primary)]' : undefined}>{isCitation ? 'Citation' : evidenceKindLabels[evidence.kind]}</span><span aria-hidden="true"> · </span><span className="font-mono">{evidence.locator}</span></p>
          </div>
          {onOpen ? <span className="inline-flex min-h-6 items-center gap-1 text-xs font-medium text-[var(--primary)]">{actionLabel}<ChevronRight className="size-3.5 transition-transform duration-[var(--duration-fast)] group-hover:translate-x-0.5 motion-reduce:transition-none" aria-hidden="true" /></span> : evidence.access !== 'available' && <Badge variant={evidence.access === 'partial' ? 'warning' : 'muted'}>{evidence.access === 'partial' ? 'Source incomplete' : 'Outdated source'}</Badge>}
        </div>
        {isCitation ? (
          <blockquote className="mt-2.5 break-words border-l-2 border-[var(--primary)] pl-3 text-xs leading-5 text-[var(--text-secondary)]">“{evidence.excerpt}”</blockquote>
        ) : (
          <p className="mt-2 break-words text-xs leading-5 text-[var(--text-secondary)]">{evidence.excerpt}</p>
        )}
      </div>
    </div>
  )

  if (onOpen) return <button type="button" onClick={onOpen} className="group block min-h-11 w-full min-w-0 p-3 text-left outline-none transition-colors duration-[var(--duration-fast)] hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)] motion-reduce:transition-none" aria-label={`${actionLabel}: ${evidence.label}`}>{content}</button>
  return <article className="min-w-0 p-3">{content}</article>
}

function DecisionPanel({ item, role, selectedOption, onSelectOption }: { item: ReviewItem; role: Role; selectedOption: string; onSelectOption: (id: string) => void }) {
  const closed = item.status === 'closed'
  const readOnly = role === 'viewer'
  const authorityRequired = !item.associateCanResolve && role !== 'owner_admin'
  const optionsDisabled = closed || readOnly || authorityRequired
  const disabledReason = item.closureReason === 'source_replaced'
    ? 'This item closed automatically because a newer source version replaced its evidence. No outdated decision was applied.'
    : closed
      ? 'This item is closed. Its recorded outcome is read-only.'
    : readOnly
      ? 'Viewer access is read-only. Viewers cannot be assigned actionable Review or record decisions.'
      : 'This decision requires Owner/Admin authority. The Associate may inspect the evidence but cannot resolve it.'

  return (
    <section aria-labelledby="decision-heading">
      <div>
        <p className="text-caption font-medium text-[var(--primary)]">Decision</p>
        <h3 id="decision-heading" className="mt-1 text-base font-semibold">{item.decision.label}</h3>
        <p className="mt-2 text-sm leading-6 text-[var(--text-secondary)]">{item.decision.instruction}</p>
      </div>
      {closed && item.recordedDecision && <div className="mt-4 rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--bg)] p-3"><p className="text-caption text-[var(--text-muted)]">Recorded outcome</p><p className="mt-1 text-sm font-medium text-[var(--text-primary)]">{item.recordedDecision.outcome}</p>{item.recordedDecision.reason && <p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">Reason: {item.recordedDecision.reason}</p>}</div>}
      {item.decision.options.length > 0 && (
        <fieldset className="mt-5 space-y-2" disabled={optionsDisabled}>
          <legend className="mb-2 text-xs font-semibold text-[var(--text-secondary)]">Select one outcome</legend>
          {item.decision.options.map((option) => {
            const selected = selectedOption === option.id
            return (
              <label key={option.id} className={cn('flex min-h-14 items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface)] p-3.5 transition-colors', !optionsDisabled && 'cursor-pointer hover:bg-[var(--surface-hover)]', selected && 'border-[var(--accent)] bg-[var(--accent-muted)]', optionsDisabled && 'opacity-70')}>
                <input type="radio" name={`decision-${item.id}`} value={option.id} checked={selected} onChange={() => onSelectOption(option.id)} className="mt-0.5 size-4 shrink-0 accent-[var(--accent)]" />
                <span className="min-w-0 flex-1"><span className="block break-words text-sm font-medium text-[var(--text-primary)]">{option.label}</span><span className="mt-1 block break-words text-xs leading-5 text-[var(--text-muted)]">{option.explanation}</span></span>
                {selected && <Check className="mt-0.5 size-4 shrink-0 text-[var(--primary)]" aria-hidden="true" />}
              </label>
            )
          })}
        </fieldset>
      )}
      {optionsDisabled && <div className={cn('mt-4 rounded-[var(--radius-sm)] border p-3', item.closureReason === 'source_replaced' ? 'border-[var(--warning)] bg-[var(--warning-muted)]' : 'border-[var(--border-subtle)] bg-[var(--bg-overlay)]')}><p className="flex items-start gap-2 text-xs leading-5 text-[var(--text-secondary)]"><LockKeyhole className="mt-0.5 size-4 shrink-0" aria-hidden="true" />{disabledReason}</p></div>}
    </section>
  )
}

function DetailContent({ item, role, activeTab, selectedOption, onSelectOption, onPreviewSource }: { item: ReviewItem; role: Role; activeTab: DetailTab; selectedOption: string; onSelectOption: (id: string) => void; onPreviewSource: (evidence?: Evidence) => void }) {
  if (activeTab === 'decision') {
    return (
      <div className="p-4 sm:p-5">
        <DecisionPanel item={item} role={role} selectedOption={selectedOption} onSelectOption={onSelectOption} />
      </div>
    )
  }
  const evidenceStatus = item.evidenceAvailability === 'Complete'
    ? 'All evidence available'
    : item.evidenceAvailability === 'Partial'
      ? `${item.evidence.filter((evidence) => evidence.access === 'available').length} of ${item.evidence.length} items fully available`
      : 'Evidence belongs to an older source'

  return (
    <div className="space-y-5 p-4">
      {item.closureReason === 'source_replaced' && <section role="status" className="rounded-[var(--radius-md)] border border-[var(--warning)] bg-[var(--warning-muted)] p-4"><div className="flex items-start gap-3"><RefreshCw className="mt-0.5 size-5 shrink-0 text-[var(--warning)]" aria-hidden="true" /><div><h3 className="text-sm font-semibold">Closed automatically · source replaced</h3><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">A newer document version made Review revision {item.revision} outdated, so no decision can be applied here. {item.replacementId ? `Open replacement item ${item.replacementId} for the current conflict.` : 'Open the current Review item instead.'}</p></div></div></section>}
      <section aria-labelledby="decision-needed-heading" className="border-b border-[var(--border)] pb-4">
        <div className="flex min-w-0 flex-wrap items-center gap-2"><Badge variant={item.status === 'closed' ? 'success' : 'warning'} className="shrink-0">{item.status === 'closed' ? 'Decision recorded' : 'Decision required'}</Badge><h3 id="decision-needed-heading" className="min-w-0 text-sm font-semibold">{item.decision.label}</h3></div>
        <p className="mt-2 text-xs leading-5 text-[var(--text-secondary)]">{item.reason}</p>
        <p className="mt-2 border-l-2 border-[var(--warning)] pl-3 text-xs leading-5 text-[var(--text-secondary)]"><span className="font-medium text-[var(--text-primary)]">What changes: </span>{item.impact}</p>
      </section>
      <section aria-labelledby="evidence-heading">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 id="evidence-heading" className="text-sm font-semibold">Supporting evidence</h3>
          <p className={cn('flex min-h-6 items-center gap-1.5 text-xs font-medium', item.evidenceAvailability === 'Complete' ? 'text-[var(--success)]' : item.evidenceAvailability === 'Partial' ? 'text-[var(--warning)]' : 'text-[var(--text-muted)]')}>{item.evidenceAvailability === 'Complete' ? <Check className="size-3.5" aria-hidden="true" /> : <AlertCircle className="size-3.5" aria-hidden="true" />}{evidenceStatus}</p>
        </div>
        <div className="mt-2.5 divide-y divide-[var(--border-subtle)] overflow-hidden rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface)]">{item.evidence.map((evidence, index) => <EvidenceCard key={evidence.id} evidence={evidence} position={index + 1} onOpen={evidence.access === 'available' && evidencePage(evidence) !== null ? () => onPreviewSource(evidence) : undefined} />)}</div>
      </section>
      <section aria-labelledby="record-context-heading" className="border-t border-[var(--border)] pt-4"><h3 id="record-context-heading" className="text-sm font-semibold">Record details</h3><p className="mt-0.5 text-xs leading-4 text-[var(--text-muted)]">Where this decision will be recorded.</p><dl className="mt-2.5 grid gap-x-5 gap-y-2.5 sm:grid-cols-2"><Fact label="Client">{item.client}</Fact><Fact label="Matter">{item.matter}</Fact><Fact label="Document">{item.document}</Fact><Fact label="Source version">{item.sourceVersion} · Review revision {item.revision}</Fact></dl></section>
    </div>
  )
}

function DetailHeader({ item, mobile, onBack, onClose }: { item: ReviewItem; mobile?: boolean; onBack?: () => void; onClose?: () => void }) {
  const Icon = typeIcons[item.type]
  return (
    <div className="shrink-0 border-b border-[var(--border)] bg-[var(--surface)] p-3">
      <div className="flex min-w-0 items-start gap-2.5">
        {mobile && <Button variant="ghost" size="icon" className="-ml-2 shrink-0" onClick={onBack} aria-label="Back to Review queue"><ArrowLeft className="size-5" aria-hidden="true" /></Button>}
        <span className="flex size-8 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--primary)]"><Icon className="size-4" aria-hidden="true" /></span>
        <div className="min-w-0 flex-1">
          <h2 className="break-words text-base font-semibold leading-5">{item.title}</h2>
          <div className="mt-1.5 flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1"><Badge fixedWidth="lg" variant={statusVariants[item.status]}>{statusLabels[item.status]}</Badge><span className="text-xs text-[var(--text-muted)]">{item.typeLabel}</span></div>
          <p className="mt-1 flex min-w-0 flex-wrap items-center gap-2"><PriorityLabel priority={item.priority} reason={item.priorityReason} /><span className="text-xs text-[var(--text-muted)]" aria-hidden="true">·</span><span className="break-words text-xs text-[var(--text-muted)]">Created {item.age} ago</span></p>
        </div>
        {!mobile && <Button variant="ghost" size="icon" className="-mr-2 shrink-0" onClick={onClose} aria-label="Close Review detail"><X className="size-4" aria-hidden="true" /></Button>}
      </div>
    </div>
  )
}

function DetailTabs({ activeTab, onChange }: { activeTab: DetailTab; onChange: (tab: DetailTab) => void }) {
  return (
    <div className="flex h-12 shrink-0 items-stretch border-b border-[var(--border-subtle)] bg-[var(--surface)] px-2" role="tablist" aria-label="Review detail sections">
      {([{ id: 'evidence', label: 'Evidence', icon: FileSearch }, { id: 'decision', label: 'Decision', icon: Check }] as const).map(({ id, label, icon: Icon }) => (
        <button key={id} type="button" role="tab" aria-selected={activeTab === id} aria-controls={`review-${id}-panel`} onClick={() => onChange(id)} className={cn('relative flex min-w-0 items-center gap-2 px-3 text-sm font-medium outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]', activeTab === id ? 'text-[var(--text-primary)] after:absolute after:inset-x-3 after:bottom-0 after:h-0.5 after:bg-[var(--accent)]' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]')}>
          <Icon className="size-4 shrink-0" aria-hidden="true" />{label}
        </button>
      ))}
    </div>
  )
}

function DecisionFooter({ item, role, activeTab, selectedOption, onContinue, onReview }: { item: ReviewItem; role: Role; activeTab: DetailTab; selectedOption: string; onContinue: () => void; onReview: () => void }) {
  const closed = item.status === 'closed'
  const canResolve = role !== 'viewer' && (item.associateCanResolve || role === 'owner_admin') && !closed
  if (activeTab === 'evidence') {
    return (
      <div className="shrink-0 border-t border-[var(--border)] bg-[var(--surface)] p-3">
        <Button className="w-full" onClick={onContinue}>{closed ? 'View recorded outcome' : 'Continue to decision'}<ChevronRight className="size-4" aria-hidden="true" /></Button>
      </div>
    )
  }
  const label = closed
    ? item.closureReason === 'dismissed' ? 'Review dismissed' : item.closureReason === 'source_replaced' ? 'Closed — source replaced' : 'Decision recorded'
    : role === 'viewer'
      ? 'Viewer cannot record decisions'
      : !canResolve
        ? 'Owner / Admin decision required'
        : selectedOption
          ? 'Review selected outcome'
          : 'Select one outcome to continue'
  return (
    <div className="shrink-0 border-t border-[var(--border)] bg-[var(--surface)] p-3">
      <Button className="w-full" disabled={!canResolve || !selectedOption} onClick={onReview}>{selectedOption && <Check className="size-4" aria-hidden="true" />}{label}</Button>
    </div>
  )
}

function DecisionReviewDialog({ item, selectedOption, open, onOpenChange }: { item: ReviewItem; selectedOption: string; open: boolean; onOpenChange: (open: boolean) => void }) {
  const option = item.decision.options.find((candidate) => candidate.id === selectedOption)
  const confirmationEffects = option?.confirmationEffects ?? [
    item.impact,
    'The supporting evidence and source version remain attached to the recorded decision.',
    'This Review item is closed and leaves the Needs review queue.',
  ]
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="overflow-hidden p-0 sm:max-w-[30rem]">
        <DialogHeader className="mb-0 border-b border-[var(--border)] px-5 py-4 pr-14">
          <div className="flex items-start gap-3">
            <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--primary)]" aria-hidden="true"><CircleCheck className="size-5" /></span>
            <div className="min-w-0">
              <DialogTitle>Record this decision?</DialogTitle>
              <DialogDescription className="mt-1 leading-6">Confirm the outcome and its effect before it becomes part of the Matter record. This concept will not save changes.</DialogDescription>
            </div>
          </div>
        </DialogHeader>
        <div className="p-5">
          <section aria-labelledby="selected-outcome-heading">
            <p id="selected-outcome-heading" className="text-caption text-[var(--text-muted)]">Selected outcome</p>
            <div className="mt-2 rounded-[var(--radius-sm)] border border-[var(--accent)] bg-[var(--accent-muted)] p-3">
              <p className="text-sm font-semibold text-[var(--text-primary)]">{option?.label ?? 'No option selected'}</p>
              <p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">{option?.explanation ?? 'Return to the decision options and choose an outcome.'}</p>
            </div>
          </section>
          <section className="mt-5" aria-labelledby="decision-effect-heading">
            <h3 id="decision-effect-heading" className="text-sm font-semibold">When confirmed</h3>
            <ul className="mt-2 space-y-2 text-sm leading-6 text-[var(--text-secondary)]">
              {confirmationEffects.map((effect) => <li key={effect} className="flex items-start gap-2"><Check className="mt-1 size-4 shrink-0 text-[var(--success)]" aria-hidden="true" /><span>{effect}</span></li>)}
            </ul>
          </section>
          <p className="mt-5 border-t border-[var(--border-subtle)] pt-3 text-xs text-[var(--text-muted)]">Source: {item.sourceVersion} · Review revision {item.revision}</p>
        </div>
        <DialogFooter className="mt-0 bg-[var(--bg)] px-5 py-4">
          <DialogClose asChild><Button variant="outline">Back to options</Button></DialogClose>
          <Button disabled>{option?.confirmLabel ?? 'Record decision'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function evidencePage(evidence: Evidence) {
  const match = evidence.locator.match(/page\s+(\d+)/i)
  return match ? Number(match[1]) : null
}

function sourcePageCount(item: ReviewItem) {
  return Math.max(1, ...item.evidence.map(evidencePage).filter((page): page is number => page !== null)) + 2
}

function ReviewViewerToolbar({ item, source, zoom, rotation, onSourceChange, onZoomChange, onRotate, onClose }: { item: ReviewItem; source: SourceContext; zoom: number; rotation: number; onSourceChange: (source: SourceContext) => void; onZoomChange: (zoom: number) => void; onRotate: () => void; onClose: () => void }) {
  const pages = sourcePageCount(item)
  const changePage = (page: number) => onSourceChange({ page: Math.max(1, Math.min(pages, page)), label: null })
  return <div className="flex h-14 shrink-0 items-center gap-2 border-b border-[var(--border)] bg-[var(--surface)] px-2 sm:px-3"><div className="mr-auto hidden min-w-0 items-center gap-2 lg:flex"><FileSearch className="size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" /><span className="max-w-64 truncate text-xs font-medium" title={item.document}>{item.document}</span></div><Button variant="ghost" size="icon" onClick={() => changePage(source.page - 1)} aria-label="Previous page"><ChevronLeft className="size-4" /></Button><span className="text-xs text-[var(--text-muted)]">Page</span><Input aria-label="Current page" value={source.page} onChange={(event) => changePage(Number(event.target.value) || 1)} className="h-9 w-12 px-2 text-center font-mono" /><span className="text-xs text-[var(--text-muted)]">/ {pages}</span><Button variant="ghost" size="icon" onClick={() => changePage(source.page + 1)} aria-label="Next page"><ChevronRight className="size-4" /></Button><span className="mx-1 hidden h-5 w-px bg-[var(--border)] sm:block" /><div className="hidden items-center sm:flex"><Button variant="ghost" size="icon" onClick={() => onZoomChange(Math.max(50, zoom - 25))} aria-label="Zoom out"><ZoomOut className="size-4" /></Button><span className="w-12 text-center font-mono text-xs text-[var(--text-muted)]">{zoom}%</span><Button variant="ghost" size="icon" onClick={() => onZoomChange(Math.min(200, zoom + 25))} aria-label="Zoom in"><ZoomIn className="size-4" /></Button><Button variant="ghost" size="icon" onClick={onRotate} aria-label={`Rotate page clockwise. Current rotation ${rotation} degrees`}><RotateCw className="size-4" /></Button></div><Button variant="ghost" size="icon" className="ml-1" onClick={onClose} aria-label="Close PDF viewer"><X className="size-5" /></Button></div>
}

function ReviewSourceViewer({ item, source, onSourceChange, onClose }: { item: ReviewItem; source: SourceContext; onSourceChange: (source: SourceContext) => void; onClose: () => void }) {
  const [zoom, setZoom] = useState(100)
  const [rotation, setRotation] = useState(0)
  const citedEvidence = item.evidence.find((evidence) => evidencePage(evidence) === source.page) ?? item.evidence[0]
  return <section aria-label={`PDF workspace for ${item.document}`} className="flex h-full min-h-0 min-w-0 flex-1 flex-col bg-[var(--bg-overlay)]"><ReviewViewerToolbar item={item} source={source} zoom={zoom} rotation={rotation} onSourceChange={onSourceChange} onZoomChange={setZoom} onRotate={() => setRotation((current) => (current + 90) % 360)} onClose={onClose} />{source.label && <div className="flex min-h-9 shrink-0 items-center gap-2 border-b border-[var(--border)] bg-[var(--accent-muted)] px-3 text-xs text-[var(--text-secondary)]"><FileSearch className="size-3.5 text-[var(--primary)]" aria-hidden="true" /><span>Showing cited source for <strong>{source.label}</strong> on page {source.page}</span></div>}<div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain p-4 sm:p-5" style={{ scrollbarGutter: 'stable' }}><article className="mx-auto min-h-[620px] w-[min(720px,calc(100%-1rem))] bg-[var(--surface)] p-8 text-[var(--text-primary)] shadow-[var(--shadow-sm)] ring-1 ring-[var(--border)] sm:p-12"><p className="text-center text-[10px] font-semibold uppercase tracking-[0.13em] text-[var(--text-muted)]">Shared PDF viewer layout · fixture source</p><h3 className="mt-10 break-words text-center text-base font-semibold">{item.document}</h3><p className="mt-2 text-center font-mono text-xs text-[var(--text-muted)]">Page {source.page} · Zoom {zoom}% · Rotation {rotation}°</p><div className="mt-10 border-y border-[var(--border-subtle)] py-5"><p className="text-caption text-[var(--text-muted)]">Review citation</p><p className="mt-2 text-sm font-medium">{citedEvidence.label}</p><p className="mt-1 font-mono text-xs text-[var(--text-muted)]">{citedEvidence.locator}</p></div><blockquote className="mt-10 border-l-2 border-[var(--primary)] bg-[var(--accent-muted)] p-4 text-sm leading-7 text-[var(--text-secondary)]">{citedEvidence.excerpt}</blockquote><p className="mt-8 text-xs leading-5 text-[var(--text-muted)]">The live workflow uses the shared PDF viewer and opens the immutable source at this cited page. This fixture demonstrates its workspace placement without reading or inventing client document contents.</p></article></div></section>
}

function DesktopDetail({ item, role, state, onClose, onPreviewSource, onRetry }: { item: ReviewItem; role: Role; state: PreviewState; onClose: () => void; onPreviewSource: (evidence?: Evidence) => void; onRetry: () => void }) {
  const ready = state === 'default' || state === 'long_content' || state === 'stale'
  const [activeTab, setActiveTab] = useState<DetailTab>('evidence')
  const [selectedOption, setSelectedOption] = useState(item.recordedDecision ? item.decision.options[0]?.id ?? '' : '')
  const [reviewOpen, setReviewOpen] = useState(false)
  return <aside className="flex min-h-0 w-[40%] min-w-[28rem] max-w-[36rem] shrink-0 flex-col overflow-hidden border-l border-[var(--border)] bg-[var(--surface)]" aria-label={`Review detail for ${item.title}`}><DetailHeader item={item} onClose={onClose} /><DetailTabs activeTab={activeTab} onChange={setActiveTab} /><div id={`review-${activeTab}-panel`} role="tabpanel" className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain" style={{ scrollbarGutter: 'stable' }}>{state === 'loading' ? <div className="space-y-3 p-4" aria-busy="true"><p className="sr-only">Loading Review evidence and decision controls…</p><Skeleton className="h-24 w-full" /><Skeleton className="h-5 w-32" /><Skeleton className="h-28 w-full" /><Skeleton className="h-28 w-full" /></div> : state === 'error' ? <StatePanel kind="error" onRetry={onRetry} /> : <DetailContent item={item} role={role} activeTab={activeTab} selectedOption={selectedOption} onSelectOption={setSelectedOption} onPreviewSource={onPreviewSource} />}</div>{ready && <DecisionFooter item={item} role={role} activeTab={activeTab} selectedOption={selectedOption} onContinue={() => setActiveTab('decision')} onReview={() => setReviewOpen(true)} />}<DecisionReviewDialog item={item} selectedOption={selectedOption} open={reviewOpen} onOpenChange={setReviewOpen} /></aside>
}

function AboutDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent showClose={false} className="sm:max-w-md"><DialogHeader><DialogTitle>Fixture-only Review concept</DialogTitle><DialogDescription>This page uses local deterministic fixtures to evaluate queue density, evidence hierarchy, decision authority, and responsive behavior. It does not read or write Review records, open source files, send notifications, or invoke RPCs.</DialogDescription></DialogHeader><DialogFooter><DialogClose asChild><Button>Close</Button></DialogClose></DialogFooter></DialogContent></Dialog>
}

function MobileDetail({ item, role, onBack, onPreviewSource }: { item: ReviewItem; role: Role; onBack: () => void; onPreviewSource: (evidence?: Evidence) => void }) {
  const [activeTab, setActiveTab] = useState<DetailTab>('evidence')
  const [selectedOption, setSelectedOption] = useState(item.recordedDecision ? item.decision.options[0]?.id ?? '' : '')
  const [reviewOpen, setReviewOpen] = useState(false)
  return <section className="flex h-full min-h-0 min-w-0 flex-col overflow-hidden bg-[var(--surface)]" aria-label={`Review detail for ${item.title}`}><DetailHeader item={item} mobile onBack={onBack} /><DetailTabs activeTab={activeTab} onChange={setActiveTab} /><div id={`review-${activeTab}-panel`} role="tabpanel" className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain" style={{ scrollbarGutter: 'stable' }}><DetailContent item={item} role={role} activeTab={activeTab} selectedOption={selectedOption} onSelectOption={setSelectedOption} onPreviewSource={onPreviewSource} /></div><DecisionFooter item={item} role={role} activeTab={activeTab} selectedOption={selectedOption} onContinue={() => setActiveTab('decision')} onReview={() => setReviewOpen(true)} /><DecisionReviewDialog item={item} selectedOption={selectedOption} open={reviewOpen} onOpenChange={setReviewOpen} /></section>
}

export function ReviewWorkspaceConcept() {
  const { resolvedTheme, setTheme } = useTheme()
  const [themeReady, setThemeReady] = useState(false)
  const dark = themeReady && resolvedTheme === 'dark'
  const [role, setRole] = useState<Role>('associate')
  const [previewState, setPreviewState] = useState<PreviewState>('default')
  const [query, setQuery] = useState('')
  const [typeFilter, setTypeFilter] = useState<TypeFilter>('all')
  const [priorityFilter, setPriorityFilter] = useState<PriorityFilter>('all')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('needs_review')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [source, setSource] = useState<SourceContext | null>(null)
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
    else if (previewState === 'stale') items = items.filter((item) => item.closureReason === 'source_replaced')
    else items = items.filter((item) => !item.longContent)

    const normalizedQuery = query.trim().toLowerCase()
    return items.filter((item) => {
      if (normalizedQuery && ![item.title, item.reason, item.impact, item.client, item.matter, item.document].some((value) => value.toLowerCase().includes(normalizedQuery))) return false
      if (typeFilter !== 'all' && item.type !== typeFilter) return false
      if (priorityFilter !== 'all' && item.priority !== priorityFilter) return false
      if (statusFilter !== 'all' && item.status !== statusFilter) return false
      return true
    })
  }, [previewState, priorityFilter, query, statusFilter, typeFilter])

  const selectedItem = visibleItems.find((item) => item.id === selectedId) ?? null

  function selectItem(item: ReviewItem, mobile: boolean) {
    setSource(null)
    if (mobile) {
      mobileListPosition.current = mobileListRef.current?.scrollTop ?? 0
      setMobileDetail(true)
    }
    setSelectedId(item.id)
  }

  function backToQueue() {
    setSource(null)
    setMobileDetail(false)
    requestAnimationFrame(() => {
      if (mobileListRef.current) mobileListRef.current.scrollTop = mobileListPosition.current
    })
  }

  function changePreview(state: PreviewState) {
    setPreviewState(state)
    setSource(null)
    setMobileDetail(false)
    setSelectedId(null)
    if (state === 'stale') setStatusFilter('closed')
    if (state === 'default') setStatusFilter('needs_review')
  }

  function openExactSource(evidence?: Evidence) {
    if (!selectedItem) return
    const cited = evidence ?? selectedItem.evidence.find((candidate) => candidate.access === 'available' && evidencePage(candidate) !== null) ?? selectedItem.evidence[0]
    const page = evidencePage(cited) ?? 1
    setSource({ page, label: cited.label })
    setAnnouncement(`Opened ${cited.label} on fixture source page ${page}.`)
  }

  function closeSource() {
    setSource(null)
    setAnnouncement('Returned to the Review queue with the selected decision preserved.')
  }

  const stateCount = previewState === 'loading' || previewState === 'empty' || previewState === 'error' ? 0 : visibleItems.length

  return (
    <div className="flex h-dvh min-w-0 flex-col overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]">
      <div className="flex min-h-0 min-w-0 flex-1 overflow-hidden">
        <ConceptRail />
        <main className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden">
          <WorkspaceHeader state={previewState} role={role} dark={dark} onState={changePreview} onRole={setRole} onDark={() => setTheme(dark ? 'light' : 'dark')} onAbout={() => setAboutOpen(true)} />
          <div className="hidden min-h-0 min-w-0 flex-1 overflow-hidden xl:flex">
            <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden">
              {source && selectedItem ? <ReviewSourceViewer key={`${selectedItem.id}-${source.label ?? 'page'}`} item={selectedItem} source={source} onSourceChange={setSource} onClose={closeSource} /> : <><QueueWorkbar query={query} type={typeFilter} priority={priorityFilter} status={statusFilter} count={stateCount} onQuery={setQuery} onType={setTypeFilter} onPriority={setPriorityFilter} onStatus={setStatusFilter} /><section aria-label="Review queue" className="custom-scrollbar min-h-0 min-w-0 flex-1 overflow-y-auto overscroll-contain bg-[var(--surface)]" style={{ scrollbarGutter: 'stable' }}><QueueBody desktop state={previewState} items={visibleItems} selectedId={selectedItem?.id ?? null} type={typeFilter} priority={priorityFilter} status={statusFilter} onType={setTypeFilter} onPriority={setPriorityFilter} onStatus={setStatusFilter} onSelect={(item) => selectItem(item, false)} onRetry={() => changePreview('default')} /></section></>}
            </div>
            {selectedItem && previewState !== 'empty' && <DesktopDetail key={selectedItem.id} item={selectedItem} role={role} state={previewState} onClose={() => { setSource(null); setSelectedId(null) }} onPreviewSource={openExactSource} onRetry={() => changePreview('default')} />}
          </div>
          <div className="min-h-0 min-w-0 flex-1 overflow-hidden xl:hidden">
            {source && selectedItem ? <ReviewSourceViewer key={`${selectedItem.id}-${source.label ?? 'page'}`} item={selectedItem} source={source} onSourceChange={setSource} onClose={() => { setSource(null); setMobileDetail(true) }} /> : mobileDetail && selectedItem ? <MobileDetail key={selectedItem.id} item={selectedItem} role={role} onBack={backToQueue} onPreviewSource={openExactSource} /> : <div className="flex h-full min-h-0 flex-col"><QueueWorkbar query={query} type={typeFilter} priority={priorityFilter} status={statusFilter} count={stateCount} onQuery={setQuery} onType={setTypeFilter} onPriority={setPriorityFilter} onStatus={setStatusFilter} /><section ref={mobileListRef} aria-label="Review queue" className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain bg-[var(--surface)]" style={{ scrollbarGutter: 'stable' }}><QueueBody state={previewState} items={visibleItems} selectedId={selectedItem?.id ?? null} type={typeFilter} priority={priorityFilter} status={statusFilter} onType={setTypeFilter} onPriority={setPriorityFilter} onStatus={setStatusFilter} onSelect={(item) => selectItem(item, true)} onRetry={() => changePreview('default')} /></section></div>}
          </div>
        </main>
      </div>
      <AboutDialog open={aboutOpen} onOpenChange={setAboutOpen} />
      <div className="sr-only" aria-live="polite">{announcement}</div>
    </div>
  )
}
