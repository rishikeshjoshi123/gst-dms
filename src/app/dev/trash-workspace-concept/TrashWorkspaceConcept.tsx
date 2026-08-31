'use client'

import { useMemo, useState } from 'react'
import {
  AlertTriangle,
  ArrowLeft,
  ChevronDown,
  ChevronRight,
  CircleAlert,
  FileText,
  Filter,
  FolderOpen,
  Gavel,
  HardDrive,
  Info,
  Loader2,
  MoreHorizontal,
  RotateCcw,
  Search,
  ShieldCheck,
  Trash2,
  Users,
  X,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
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
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { cn } from '@/lib/utils'

type ResourceType = 'Client' | 'Matter' | 'Document'
type ResourceFilter = 'All' | ResourceType
type SampleState = 'default' | 'loading' | 'empty' | 'error'
type PreviewAction = 'restore' | 'delete'

type TrashOperation = {
  id: string
  type: ResourceType
  name: string
  parent: string
  deletedBy: string
  deletedAt: string
  reason: string
  descendants: string
  size: string
  tree: Array<{ type: ResourceType; name: string; detail: string; route: string }>
}

const operations: TrashOperation[] = [
  {
    id: 'op-418', type: 'Client', name: 'Kaveri Components Private Limited', parent: 'Organisation client register', deletedBy: 'Rishikesh Joshi', deletedAt: '30 Aug 2026 · 10:32', reason: 'Duplicate client record after merger', descendants: '4 matters · 28 documents', size: '48.6 MB',
    tree: [
      { type: 'Matter', name: 'FY 2024–25 ITC reconciliation', detail: 'Moved with Kaveri Components Private Limited', route: '/matters/kaveri-itc-2024' },
      { type: 'Document', name: 'Supplier confirmations — consolidated ledger and annexures for Q4 FY 2024–25.pdf', detail: 'Moved with its parent · 11.2 MB', route: '/documents/kaveri-supplier-confirmations' },
      { type: 'Document', name: 'GST reconciliation workbook.xlsx', detail: 'Moved with its parent · 2.8 MB', route: '/documents/kaveri-reconciliation' },
      { type: 'Matter', name: 'Classification advisory', detail: 'Moved with Kaveri Components Private Limited', route: '/matters/kaveri-classification' },
    ],
  },
  {
    id: 'op-417', type: 'Matter', name: 'Apex Auto Components — FY 2022 audit response', parent: 'Apex Auto Components', deletedBy: 'Ananya Kapoor', deletedAt: '29 Aug 2026 · 16:08', reason: 'Matter superseded by consolidated audit file', descendants: '12 documents · 3 notes', size: '19.4 MB',
    tree: [
      { type: 'Document', name: 'Audit response — final signed.pdf', detail: 'Moved with its parent · 4.1 MB', route: '/documents/apex-audit-final' },
      { type: 'Document', name: 'Supporting invoices — batch 1.zip', detail: 'Moved with its parent · 13.7 MB', route: '/documents/apex-invoices-batch-1' },
    ],
  },
  {
    id: 'op-416', type: 'Document', name: 'Notice_17-2025_scanned_copy.pdf', parent: 'Mehta Industrial · DRC-01 response', deletedBy: 'Meera Shah', deletedAt: '28 Aug 2026 · 11:46', reason: 'Unreadable duplicate scan', descendants: 'No included items', size: '6.2 MB', tree: [],
  },
  {
    id: 'op-415', type: 'Document', name: 'Evidence bundle — plant photographs and witness notes (archived copy).pdf', parent: 'Suryodaya Textiles · Classification appeal', deletedBy: 'Rishikesh Joshi', deletedAt: '27 Aug 2026 · 09:15', reason: 'Replaced by verified bundle', descendants: 'No included items', size: '26.9 MB', tree: [],
  },
]

const typeIcon = { Client: Users, Matter: FolderOpen, Document: FileText }

function ResourceMark({ type }: { type: ResourceType }) {
  const Icon = typeIcon[type]
  return <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] text-[var(--text-secondary)]"><Icon className="size-4" aria-hidden="true" /></span>
}

function ResourceTypeMenu({ value, onChange }: { value: ResourceFilter; onChange: (value: ResourceFilter) => void }) {
  const label = value === 'All' ? 'All types' : `${value}s`
  return <DropdownMenu>
    <DropdownMenuTrigger asChild><Button variant="outline" size="sm" className="shrink-0"><Filter className="size-4" />{label}<ChevronDown className="size-3.5" /></Button></DropdownMenuTrigger>
    <DropdownMenuContent align="start">
      <DropdownMenuLabel>Resource type</DropdownMenuLabel><DropdownMenuSeparator />
      {(['All', 'Client', 'Matter', 'Document'] as ResourceFilter[]).map((option) => <DropdownMenuCheckboxItem key={option} checked={value === option} onCheckedChange={() => onChange(option)}>{option === 'All' ? 'All types' : `${option}s`}</DropdownMenuCheckboxItem>)}
    </DropdownMenuContent>
  </DropdownMenu>
}

function PreviewMenu({ state, onStateChange, onShowBoundary }: { state: SampleState; onStateChange: (state: SampleState) => void; onShowBoundary: () => void }) {
  return <DropdownMenu>
    <DropdownMenuTrigger asChild><Button variant="outline" size="sm" className="shrink-0"><MoreHorizontal className="size-4" />Preview<ChevronDown className="size-3.5" /></Button></DropdownMenuTrigger>
    <DropdownMenuContent align="end">
      <DropdownMenuLabel>Preview state</DropdownMenuLabel><DropdownMenuSeparator />
      {(['default', 'loading', 'empty', 'error'] as SampleState[]).map((option) => <DropdownMenuCheckboxItem key={option} checked={state === option} onCheckedChange={() => onStateChange(option)} className="capitalize">{option}</DropdownMenuCheckboxItem>)}
      <DropdownMenuSeparator />
      <DropdownMenuItem onSelect={onShowBoundary}><Info className="size-4" />About this concept</DropdownMenuItem>
    </DropdownMenuContent>
  </DropdownMenu>
}

function OperationRow({ operation, selected, onSelect }: { operation: TrashOperation; selected: boolean; onSelect: () => void }) {
  return <TableRow interactive selected={selected}>
    <TableCell><button type="button" onClick={onSelect} className="flex min-h-11 min-w-0 items-center gap-3 text-left"><ResourceMark type={operation.type} /><span className="min-w-0"><span className="block max-w-[360px] truncate text-sm font-semibold text-[var(--text-primary)]">{operation.name}</span><span className="mt-0.5 block max-w-[360px] truncate text-xs text-[var(--text-muted)]">{operation.type} · {operation.parent}</span></span></button></TableCell>
    <TableCell className="text-xs leading-5 text-[var(--text-secondary)]"><span className="block font-medium text-[var(--text-primary)]">{operation.deletedBy}</span><span className="block font-mono text-[var(--text-muted)]">{operation.deletedAt}</span></TableCell>
    <TableCell className="text-xs leading-5 text-[var(--text-secondary)]"><span className="block">{operation.descendants}</span><span className="block font-mono text-[var(--text-muted)]">{operation.size}</span></TableCell>
    <TableCell><Button variant="ghost" size="sm" onClick={onSelect} className="min-h-11 whitespace-nowrap">View details</Button></TableCell>
  </TableRow>
}

function DetailPanel({ operation, onClose, onPreviewAction, mobile = false }: { operation: TrashOperation; onClose: () => void; onPreviewAction: (action: PreviewAction) => void; mobile?: boolean }) {
  const RootIcon = typeIcon[operation.type]
  return <aside aria-label={`Trash details for ${operation.name}`} className={cn('flex h-full min-h-0 flex-1 flex-col bg-[var(--surface)]', !mobile && 'border-l border-[var(--border-subtle)] xl:w-full xl:max-w-md xl:shrink-0')}>
    <div className="flex h-14 shrink-0 items-center gap-2 border-b border-[var(--border-subtle)] px-4">{mobile ? <Button variant="ghost" size="sm" className="-ml-2" onClick={onClose}><ArrowLeft className="size-4" />Back to Trash</Button> : <><Trash2 className="size-4 text-[var(--accent)]" /><span className="text-sm font-semibold">Trash details</span><Button variant="ghost" size="icon" className="ml-auto" onClick={onClose} aria-label="Close Trash details"><X className="size-4" /></Button></>}</div>
    <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain p-4">
      <div className="flex items-start gap-3"><span className="flex size-10 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--accent)]"><RootIcon className="size-5" /></span><div className="min-w-0"><p className="text-sm font-semibold">{operation.name}</p><p className="mt-0.5 text-xs text-[var(--text-muted)]">Original context: {operation.parent}</p></div></div>
      <p className="mt-1 pl-[52px] text-xs text-[var(--text-muted)]">Group {operation.id} · {operation.descendants}</p>
      <div className="mt-4 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3 text-xs leading-5 text-[var(--text-secondary)]"><Info className="mr-1 inline size-4 align-text-bottom text-[var(--text-muted)]" />Preview only—these controls do not change data. Permanent deletion will be available only to Owner/Admin in production.</div>
      <dl className="mt-5 grid grid-cols-2 gap-x-4 gap-y-4 border-y border-[var(--border-subtle)] py-4 text-xs"><div><dt className="text-[var(--text-muted)]">Deleted by</dt><dd className="mt-1 font-medium text-[var(--text-primary)]">{operation.deletedBy}</dd></div><div><dt className="text-[var(--text-muted)]">Deleted on</dt><dd className="mt-1 font-mono text-[var(--text-primary)]">{operation.deletedAt}</dd></div><div><dt className="text-[var(--text-muted)]">Storage in Trash</dt><dd className="mt-1 font-mono text-[var(--text-primary)]">{operation.size}</dd></div><div className="col-span-2"><dt className="text-[var(--text-muted)]">Reason</dt><dd className="mt-1 text-[var(--text-primary)]">{operation.reason}</dd></div></dl>
      <section className="mt-5"><div className="flex items-center justify-between gap-2"><h3 className="text-sm font-semibold">Items moved together</h3><span className="text-xs text-[var(--text-muted)]">{operation.descendants}</span></div><ul className="mt-3 space-y-2">{operation.tree.length ? operation.tree.map((node) => { const Icon = typeIcon[node.type]; return <li key={node.route}><div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3"><div className="flex gap-2"><Icon className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" /><div className="min-w-0 flex-1"><p className="truncate text-sm font-medium">{node.name}</p><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">{node.detail}</p><div className="mt-2 flex flex-wrap items-center gap-2"><Badge variant="muted" fixedWidth="lg">Included</Badge><a href={node.route} className="text-xs font-medium text-[var(--primary)] underline-offset-2 hover:underline">Open item later</a></div></div></div></div></li> }) : <li className="text-sm text-[var(--text-muted)]">No other items were moved with this document.</li>}</ul></section>
      <Card padding="none" className="mt-5 !rounded-[var(--radius-sm)] !border-[var(--border-subtle)] !bg-[var(--bg)]"><CardHeader className="p-3"><CardTitle className="flex items-center gap-2 text-sm"><ShieldCheck className="size-4 text-[var(--text-muted)]" />Why items are grouped</CardTitle><CardDescription className="mt-1 text-xs leading-5">Items moved with a client or matter cannot be restored or permanently deleted one by one. Any future action applies to the whole Trash group.</CardDescription></CardHeader><CardContent className="sr-only">Actions apply to the whole Trash group.</CardContent></Card>
    </div>
    <div className="flex shrink-0 flex-wrap items-center justify-end gap-2 border-t border-[var(--border-subtle)] p-3"><Button size="sm" onClick={() => onPreviewAction('restore')}><RotateCcw className="size-4" />Restore group</Button><Button variant="destructive" size="sm" onClick={() => onPreviewAction('delete')}><Trash2 className="size-4" />Delete permanently</Button></div>
  </aside>
}

function ActionPreviewDialog({ action, operation, onClose }: { action: PreviewAction | null; operation: TrashOperation | null; onClose: () => void }) {
  const deleting = action === 'delete'
  return <Dialog open={Boolean(action && operation)} onOpenChange={(open) => !open && onClose()}><DialogContent><DialogHeader><DialogTitle>{deleting ? 'Delete this Trash group permanently?' : 'Restore this Trash group?'}</DialogTitle><DialogDescription>{deleting ? 'Permanent deletion applies to the selected item and everything moved to Trash with it.' : 'Restoring applies to the selected item and everything moved to Trash with it.'}</DialogDescription></DialogHeader>{operation && <><dl className="grid grid-cols-2 gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3 text-xs"><div className="col-span-2"><dt className="text-[var(--text-muted)]">Trash group</dt><dd className="mt-1 font-medium text-[var(--text-primary)]">{operation.name}</dd></div><div><dt className="text-[var(--text-muted)]">Included</dt><dd className="mt-1 text-[var(--text-primary)]">{operation.descendants}</dd></div><div><dt className="text-[var(--text-muted)]">Storage</dt><dd className="mt-1 font-mono text-[var(--text-primary)]">{operation.size}</dd></div></dl><div className={cn('mt-4 rounded-[var(--radius-sm)] border p-3 text-sm leading-6', deleting ? 'border-[var(--danger)] bg-[var(--danger-muted)] text-[var(--text-secondary)]' : 'border-[var(--border-subtle)] bg-[var(--bg)] text-[var(--text-secondary)]')}>{deleting ? 'This cannot be undone. Production requires Owner/Admin permission, recent authentication, blocker checks, an exact impact preview, and typed confirmation.' : 'Items included with a client or matter return together. They cannot be restored separately from this group.'}</div></>}<DialogFooter><Button variant="outline" onClick={onClose}>Close preview</Button><Button variant={deleting ? 'destructive' : 'default'} disabled>{deleting ? 'Delete permanently' : 'Restore group'}</Button></DialogFooter></DialogContent></Dialog>
}

function MobileOperationCard({ operation, onSelect }: { operation: TrashOperation; onSelect: () => void }) {
  return <button type="button" onClick={onSelect} className="w-full rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4 text-left hover:bg-[var(--surface-hover)]"><div className="flex gap-3"><ResourceMark type={operation.type} /><div className="min-w-0 flex-1"><span className="text-xs font-medium text-[var(--text-muted)]">{operation.type}</span><h2 className="mt-1 truncate text-sm font-semibold">{operation.name}</h2><p className="mt-1 truncate text-xs text-[var(--text-muted)]">{operation.parent}</p></div></div><div className="mt-3 grid grid-cols-2 gap-3 border-t border-[var(--border-subtle)] pt-3 text-xs"><span><span className="block text-[var(--text-muted)]">Deleted</span><span className="mt-0.5 block text-[var(--text-secondary)]">{operation.deletedAt}</span></span><span><span className="block text-[var(--text-muted)]">Included</span><span className="mt-0.5 block text-[var(--text-secondary)]">{operation.descendants}</span></span></div></button>
}

function TrashTableColumns() {
  return <colgroup><col className="w-[48%]" /><col className="w-[25%]" /><col className="w-[18%]" /><col className="w-[120px]" /></colgroup>
}

function TrashTableHeader({ loading = false }: { loading?: boolean }) {
  return <TableHeader sticky><TableRow><TableHead>Item</TableHead><TableHead>Deleted</TableHead><TableHead>Included</TableHead><TableHead>{loading ? <span className="flex items-center justify-end gap-1.5"><Loader2 className="size-3.5 animate-spin motion-reduce:animate-none" />Loading</span> : <span className="sr-only">View details</span>}</TableHead></TableRow></TableHeader>
}

function OperationRowSkeleton() {
  return <TableRow aria-hidden="true">
    <TableCell><div className="flex min-h-11 min-w-0 items-center gap-3"><Skeleton className="size-9 shrink-0" /><span className="min-w-0 flex-1"><Skeleton className="h-3.5 w-4/5 max-w-72" /><Skeleton className="mt-2 h-3 w-3/5 max-w-56" /></span></div></TableCell>
    <TableCell><Skeleton className="h-3.5 w-28" /><Skeleton className="mt-2 h-3 w-36" /></TableCell>
    <TableCell><Skeleton className="h-3 w-28" /><Skeleton className="mt-2 h-3 w-16" /></TableCell>
    <TableCell><Skeleton className="h-9 w-24" /></TableCell>
  </TableRow>
}

function MobileOperationCardSkeleton() {
  return <div className="w-full rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4" aria-hidden="true"><div className="flex gap-3"><Skeleton className="size-9 shrink-0" /><div className="min-w-0 flex-1"><Skeleton className="h-3 w-16" /><Skeleton className="mt-2 h-3.5 w-4/5" /><Skeleton className="mt-2 h-3 w-3/5" /></div></div><div className="mt-3 grid grid-cols-2 gap-3 border-t border-[var(--border-subtle)] pt-3"><span><Skeleton className="h-3 w-12" /><Skeleton className="mt-2 h-3 w-4/5" /></span><span><Skeleton className="h-3 w-12" /><Skeleton className="mt-2 h-3 w-3/5" /></span></div></div>
}

function StateBody({ state, operations, selected, onSelect, onRetry }: { state: SampleState; operations: TrashOperation[]; selected: string | null; onSelect: (id: string) => void; onRetry: () => void }) {
  if (state === 'loading') return <div aria-busy="true" aria-live="polite"><p className="sr-only">Loading Trash groups…</p><div className="hidden min-w-[720px] md:block"><Table className="table-fixed"><TableCaption>Loading Trash groups.</TableCaption><TrashTableColumns /><TrashTableHeader loading /><TableBody>{[1, 2, 3, 4].map((item) => <OperationRowSkeleton key={item} />)}</TableBody></Table></div><div className="space-y-3 p-3 md:hidden">{[1, 2, 3].map((item) => <MobileOperationCardSkeleton key={item} />)}</div></div>
  if (state === 'empty') return <div className="grid min-h-[360px] place-items-center p-6 text-center"><div><Trash2 className="mx-auto size-8 text-[var(--text-muted)]" /><h2 className="mt-3 text-section-heading">No Trash entries match</h2><p className="mx-auto mt-2 max-w-md text-sm text-[var(--text-muted)]">Try a broader search or show all resource types. Items moved together appear within one entry.</p></div></div>
  if (state === 'error') return <div className="grid min-h-[360px] place-items-center p-6 text-center"><div><CircleAlert className="mx-auto size-8 text-[var(--danger)]" /><h2 className="mt-3 text-section-heading">Trash could not be displayed</h2><p className="mx-auto mt-2 max-w-md text-sm text-[var(--text-muted)]">The list did not load. Try again without changing anything in Trash.</p><Button variant="outline" className="mt-4" onClick={onRetry}>Try again</Button></div></div>
  return <><div className="hidden min-w-[720px] md:block"><Table className="table-fixed"><TableCaption>Trash groups. Select one to view the items moved together.</TableCaption><TrashTableColumns /><TrashTableHeader /><TableBody>{operations.map((operation) => <OperationRow key={operation.id} operation={operation} selected={operation.id === selected} onSelect={() => onSelect(operation.id)} />)}</TableBody></Table></div><div className="space-y-3 p-3 md:hidden">{operations.map((operation) => <MobileOperationCard key={operation.id} operation={operation} onSelect={() => onSelect(operation.id)} />)}</div></>
}

export function TrashWorkspaceConcept() {
  const [sampleState, setSampleState] = useState<SampleState>('default')
  const [query, setQuery] = useState('')
  const [resourceType, setResourceType] = useState<ResourceFilter>('All')
  const [selectedId, setSelectedId] = useState<string | null>('op-418')
  const [noticeOpen, setNoticeOpen] = useState(false)
  const [actionPreview, setActionPreview] = useState<PreviewAction | null>(null)
  const visibleOperations = useMemo(() => operations.filter((operation) => (resourceType === 'All' || operation.type === resourceType) && `${operation.name} ${operation.parent} ${operation.deletedBy}`.toLowerCase().includes(query.toLowerCase())), [query, resourceType])
  const selected = operations.find((operation) => operation.id === selectedId) ?? null

  return <div className="flex h-dvh overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]"><aside className="hidden w-16 shrink-0 flex-col items-center border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] py-3 text-[var(--sidebar-text)] lg:flex"><span className="flex size-10 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]"><Gavel className="size-5" /></span><span className="mt-auto flex size-11 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]" aria-label="Trash"><Trash2 className="size-5" /></span></aside><main className="flex min-w-0 flex-1 flex-col overflow-hidden"><header className="shrink-0 border-b border-[var(--border)] bg-[var(--surface)]"><div className="flex min-h-12 items-center gap-2 border-b border-[var(--border-subtle)] px-4 text-xs text-[var(--text-muted)]"><span>Apex Tax Advocates</span><ChevronRight className="size-3.5" /><span>Organisation utilities</span><ChevronRight className="size-3.5" /><span className="text-[var(--text-primary)]">Trash</span></div><div className="flex min-h-14 shrink-0 flex-wrap items-center gap-x-2 gap-y-1 px-3 py-1.5 sm:flex-nowrap sm:px-4 sm:py-0"><div className="relative w-full sm:w-72 lg:w-80"><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" /><Input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search Trash" aria-label="Search Trash" className="pl-9" /></div><ResourceTypeMenu value={resourceType} onChange={setResourceType} /><div className="ml-auto flex items-center gap-3"><span className="hidden items-center gap-1.5 text-xs text-[var(--text-muted)] sm:flex"><HardDrive className="size-3.5" />101.1 MB in Trash</span><PreviewMenu state={sampleState} onStateChange={setSampleState} onShowBoundary={() => setNoticeOpen(true)} /></div></div></header><div className="min-h-0 flex-1 overflow-hidden"><div className="hidden h-full min-h-0 md:flex"><section aria-label="Trash groups" className={cn('min-w-0 flex-1 overflow-y-auto overscroll-contain', selected && 'xl:block', selected && 'hidden xl:block')}><StateBody state={sampleState} operations={visibleOperations} selected={selectedId} onSelect={setSelectedId} onRetry={() => setSampleState('default')} /></section>{selected && <DetailPanel operation={selected} onClose={() => setSelectedId(null)} onPreviewAction={setActionPreview} />}</div><div className="h-full overflow-hidden md:hidden">{selected ? <DetailPanel operation={selected} onClose={() => setSelectedId(null)} onPreviewAction={setActionPreview} mobile /> : <section aria-label="Trash groups"><StateBody state={sampleState} operations={visibleOperations} selected={selectedId} onSelect={setSelectedId} onRetry={() => setSampleState('default')} /></section>}</div></div></main><ActionPreviewDialog action={actionPreview} operation={selected} onClose={() => setActionPreview(null)} /><Dialog open={noticeOpen} onOpenChange={setNoticeOpen}><DialogContent><DialogHeader><DialogTitle>Approval concept — no live actions</DialogTitle><DialogDescription>This browser concept illustrates the Trash list, responsive item grouping, and future group-scoped actions. It has no API calls, server actions, restore, permanent-delete, or permission enforcement.</DialogDescription></DialogHeader><div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3 text-sm text-[var(--text-secondary)]"><AlertTriangle className="mr-2 inline size-4 text-[var(--warning)]" />Restore and permanent-delete controls open preview-only impact dialogs. Included items do not expose independent actions.</div><DialogFooter><Button onClick={() => setNoticeOpen(false)}>Understand</Button></DialogFooter></DialogContent></Dialog></div>
}
