'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import {
  ArrowLeft,
  ChevronDown,
  FileText,
  Filter,
  FolderOpen,
  HardDrive,
  Info,
  Loader2,
  Search,
  Trash2,
  Users,
  X,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Input } from '@/components/ui/input'
import {
  Table,
  TableBody,
  TableCaption,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { cn } from '@/lib/utils'
import {
  describeIncludedItems,
  type TrashIncludedItem,
  type TrashOperation,
  type TrashResourceFilter,
  type TrashResourceType,
  type TrashWorkspaceData,
} from '@/lib/trash/workspace-model'

const typeIcon = { client: Users, matter: FolderOpen, document: FileText }
const typeLabel = { client: 'Client', matter: 'Matter', document: 'Document' }

function formatBytes(value: number) {
  if (!Number.isFinite(value) || value <= 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const exponent = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1)
  const amount = value / (1024 ** exponent)
  return `${new Intl.NumberFormat('en-IN', { maximumFractionDigits: amount < 10 ? 1 : 0 }).format(amount)} ${units[exponent]}`
}

function formatDeletedAt(value: string, timeZone: string) {
  try {
    return new Intl.DateTimeFormat('en-IN', {
      dateStyle: 'medium',
      timeStyle: 'short',
      timeZone,
    }).format(new Date(value))
  } catch {
    return new Intl.DateTimeFormat('en-IN', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  }
}

function ResourceMark({ type }: { type: TrashResourceType }) {
  const Icon = typeIcon[type]
  return (
    <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] text-[var(--text-secondary)]">
      <Icon className="size-4" aria-hidden="true" />
    </span>
  )
}

function filterLabel(filter: TrashResourceFilter) {
  if (filter === 'all') return 'All types'
  return `${typeLabel[filter]}s`
}

function IncludedTree({ operation }: { operation: TrashOperation }) {
  const byParent = new Map<string, TrashIncludedItem[]>()
  for (const item of operation.includedItems) {
    const siblings = byParent.get(item.parentMembershipId) ?? []
    siblings.push(item)
    byParent.set(item.parentMembershipId, siblings)
  }

  const renderItems = (parentMembershipId: string, depth = 0): React.ReactNode => {
    const items = byParent.get(parentMembershipId) ?? []
    if (!items.length) return null
    return (
      <ul className={cn('space-y-2', depth > 0 && 'mt-2 border-l border-[var(--border-subtle)] pl-3')}>
        {items.map((item) => {
          const Icon = typeIcon[item.resourceType]
          return (
            <li key={item.membershipId}>
              <div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3">
                <div className="flex min-w-0 gap-2.5">
                  <Icon className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" />
                  <div className="min-w-0 flex-1">
                    <p className="break-words text-sm font-medium text-[var(--text-primary)]">{item.name}</p>
                    <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">
                      {typeLabel[item.resourceType]} moved with this Trash group
                    </p>
                    <div className="mt-2 flex flex-wrap items-center gap-2">
                      <Badge variant="muted" fixedWidth="lg">Included</Badge>
                      <span className="inline-flex min-h-8 items-center text-xs text-[var(--text-muted)]">
                        Read-only item page is not available yet
                      </span>
                    </div>
                  </div>
                </div>
              </div>
              {renderItems(item.membershipId, depth + 1)}
            </li>
          )
        })}
      </ul>
    )
  }

  const tree = renderItems(operation.rootMembershipId)
  return tree ?? <p className="text-sm text-[var(--text-muted)]">No other items were moved with this document.</p>
}

function OperationRow({ operation, selected, timeZone, onSelect }: {
  operation: TrashOperation
  selected: boolean
  timeZone: string
  onSelect: () => void
}) {
  return (
    <TableRow interactive selected={selected}>
      <TableCell>
        <button type="button" onClick={onSelect} className="flex min-h-11 min-w-0 items-center gap-3 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">
          <ResourceMark type={operation.resourceType} />
          <span className="min-w-0">
            <span className="block max-w-[360px] truncate text-sm font-semibold text-[var(--text-primary)]">{operation.name}</span>
            <span className="mt-0.5 block max-w-[360px] truncate text-xs text-[var(--text-muted)]">
              {typeLabel[operation.resourceType]} · {operation.parentContext}
            </span>
          </span>
        </button>
      </TableCell>
      <TableCell className="text-xs leading-5 text-[var(--text-secondary)]">
        <span className="block font-medium text-[var(--text-primary)]">{operation.deletedBy}</span>
        <span className="block font-mono text-[var(--text-muted)]">{formatDeletedAt(operation.deletedAt, timeZone)}</span>
      </TableCell>
      <TableCell className="text-xs leading-5 text-[var(--text-secondary)]">
        <span className="block">{describeIncludedItems(operation)}</span>
        <span className="block font-mono text-[var(--text-muted)]">{formatBytes(operation.storageBytes)}</span>
      </TableCell>
      <TableCell className="text-right">
        <Button variant="ghost" size="sm" onClick={onSelect} className="min-h-11 whitespace-nowrap">View details</Button>
      </TableCell>
    </TableRow>
  )
}

function MobileOperationCard({ operation, timeZone, onSelect }: {
  operation: TrashOperation
  timeZone: string
  onSelect: () => void
}) {
  return (
    <button
      type="button"
      onClick={onSelect}
      className="w-full rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4 text-left transition-colors hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
      aria-label={`View details for ${operation.name}`}
    >
      <div className="flex gap-3">
        <ResourceMark type={operation.resourceType} />
        <div className="min-w-0 flex-1">
          <span className="text-xs font-medium text-[var(--text-muted)]">{typeLabel[operation.resourceType]}</span>
          <h2 className="mt-1 break-words text-sm font-semibold text-[var(--text-primary)]">{operation.name}</h2>
          <p className="mt-1 break-words text-xs text-[var(--text-muted)]">{operation.parentContext}</p>
        </div>
      </div>
      <div className="mt-3 grid grid-cols-2 gap-3 border-t border-[var(--border-subtle)] pt-3 text-xs">
        <span>
          <span className="block text-[var(--text-muted)]">Deleted</span>
          <span className="mt-0.5 block text-[var(--text-secondary)]">{formatDeletedAt(operation.deletedAt, timeZone)}</span>
        </span>
        <span>
          <span className="block text-[var(--text-muted)]">Included</span>
          <span className="mt-0.5 block text-[var(--text-secondary)]">{describeIncludedItems(operation)}</span>
        </span>
      </div>
    </button>
  )
}

function EmptyState({ filtered }: { filtered: boolean }) {
  return (
    <div className="grid min-h-72 place-items-center p-6 text-center">
      <div>
        <Trash2 className="mx-auto size-8 text-[var(--text-muted)]" aria-hidden="true" />
        <h2 className="mt-3 text-section-heading">{filtered ? 'No Trash entries match' : 'Trash is empty'}</h2>
        <p className="mx-auto mt-2 max-w-md text-sm text-[var(--text-muted)]">
          {filtered ? 'Try a broader search or show all resource types.' : 'Items moved to Trash will appear here as one entry for each grouped deletion.'}
        </p>
      </div>
    </div>
  )
}

function OperationCollection({ operations, selectedId, timeZone, filtered, onSelect }: {
  operations: TrashOperation[]
  selectedId: string | null
  timeZone: string
  filtered: boolean
  onSelect: (id: string) => void
}) {
  if (!operations.length) return <EmptyState filtered={filtered} />
  return (
    <>
      <div className="hidden min-w-[720px] lg:block">
        <Table className="table-fixed">
          <TableCaption>Trash groups. Select one to inspect the items moved together.</TableCaption>
          <colgroup><col className="w-[48%]" /><col className="w-[25%]" /><col className="w-[18%]" /><col className="w-[120px]" /></colgroup>
          <TableHeader sticky>
            <TableRow><TableHead>Item</TableHead><TableHead>Deleted</TableHead><TableHead>Included</TableHead><TableHead><span className="sr-only">View details</span></TableHead></TableRow>
          </TableHeader>
          <TableBody>
            {operations.map((operation) => (
              <OperationRow key={operation.id} operation={operation} selected={selectedId === operation.id} timeZone={timeZone} onSelect={() => onSelect(operation.id)} />
            ))}
          </TableBody>
        </Table>
      </div>
      <div className="space-y-3 p-3 lg:hidden">
        {operations.map((operation) => <MobileOperationCard key={operation.id} operation={operation} timeZone={timeZone} onSelect={() => onSelect(operation.id)} />)}
      </div>
    </>
  )
}

function DetailPanel({ operation, timeZone, mobile, onClose }: {
  operation: TrashOperation
  timeZone: string
  mobile?: boolean
  onClose: () => void
}) {
  const RootIcon = typeIcon[operation.resourceType]
  return (
    <aside
      aria-label={`Trash details for ${operation.name}`}
      className={cn('flex h-full min-h-0 flex-1 flex-col bg-[var(--surface)]', !mobile && 'xl:w-full xl:max-w-md xl:shrink-0 xl:border-l xl:border-[var(--border-subtle)]')}
    >
      <div className="flex min-h-14 shrink-0 items-center gap-2 border-b border-[var(--border-subtle)] px-3 sm:px-4">
        {mobile ? (
          <Button variant="ghost" size="sm" className="-ml-2" onClick={onClose}><ArrowLeft className="size-4" />Back to Trash</Button>
        ) : (
          <>
            <Trash2 className="size-4 text-[var(--accent)]" aria-hidden="true" />
            <span className="text-sm font-semibold">Trash details</span>
            <Button variant="ghost" size="icon" className="ml-auto" onClick={onClose} aria-label="Close Trash details"><X className="size-4" /></Button>
          </>
        )}
      </div>
      <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain p-4">
        <div className="flex items-start gap-3">
          <span className="flex size-10 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--accent)]"><RootIcon className="size-5" aria-hidden="true" /></span>
          <div className="min-w-0">
            <h2 className="break-words text-sm font-semibold text-[var(--text-primary)]">{operation.name}</h2>
            <p className="mt-0.5 break-words text-xs text-[var(--text-muted)]">Original context: {operation.parentContext}</p>
          </div>
        </div>
        <div className="mt-4 flex items-start gap-2 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3 text-xs leading-5 text-[var(--text-secondary)]">
          <Info className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" />
          <span>Trash is read-only here. Opening trashed Client, Matter, and Document pages will be enabled with the later read-only route update.</span>
        </div>
        <dl className="mt-5 grid grid-cols-2 gap-x-4 gap-y-4 border-y border-[var(--border-subtle)] py-4 text-xs">
          <div><dt className="text-[var(--text-muted)]">Deleted by</dt><dd className="mt-1 font-medium text-[var(--text-primary)]">{operation.deletedBy}</dd></div>
          <div><dt className="text-[var(--text-muted)]">Deleted on</dt><dd className="mt-1 font-mono text-[var(--text-primary)]">{formatDeletedAt(operation.deletedAt, timeZone)}</dd></div>
          <div><dt className="text-[var(--text-muted)]">Storage in Trash</dt><dd className="mt-1 font-mono text-[var(--text-primary)]">{formatBytes(operation.storageBytes)}</dd></div>
          <div className="col-span-2"><dt className="text-[var(--text-muted)]">Reason</dt><dd className="mt-1 break-words text-[var(--text-primary)]">{operation.reason?.trim() || 'No reason was recorded.'}</dd></div>
        </dl>
        <section className="mt-5" aria-labelledby="included-items-heading">
          <div className="flex items-start justify-between gap-3">
            <h3 id="included-items-heading" className="text-sm font-semibold">Items moved together</h3>
            <span className="text-right text-xs text-[var(--text-muted)]">{describeIncludedItems(operation)}</span>
          </div>
          <div className="mt-3"><IncludedTree operation={operation} /></div>
        </section>
        <div className="mt-5 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3">
          <h3 className="text-sm font-semibold">Grouped item boundary</h3>
          <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Included items belong to this root Trash group and have no independent actions.</p>
        </div>
      </div>
    </aside>
  )
}

export function TrashWorkspace({ data, query, resourceType }: {
  data: TrashWorkspaceData
  query: string
  resourceType: TrashResourceFilter
}) {
  const router = useRouter()
  const [searchValue, setSearchValue] = useState(query)
  const [isPending, startTransition] = useTransition()
  const selectedId = data.selectedOperation?.id ?? null
  const filtered = Boolean(query || resourceType !== 'all')

  const navigate = (next: { query?: string; type?: TrashResourceFilter; selected?: string | null }) => {
    const params = new URLSearchParams()
    const nextQuery = next.query ?? query
    const nextType = next.type ?? resourceType
    const nextSelection = next.selected === undefined ? selectedId : next.selected
    if (nextQuery) params.set('q', nextQuery)
    if (nextType !== 'all') params.set('type', nextType)
    if (nextSelection) params.set('selected', nextSelection)
    startTransition(() => router.replace(params.size ? `/trash?${params}` : '/trash', { scroll: false }))
  }

  const chooseType = (type: TrashResourceFilter) => navigate({ type, selected: null })

  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Organisation utilities' }, { label: 'Trash' }]} />
      <div className="flex min-h-14 shrink-0 flex-wrap items-center gap-2 border-b border-[var(--border-subtle)] px-3 py-1.5 sm:flex-nowrap sm:px-4">
        <form
          className="flex w-full min-w-0 items-center gap-2 sm:w-auto"
          role="search"
          onSubmit={(event) => {
            event.preventDefault()
            navigate({ query: searchValue.trim().slice(0, 120), selected: null })
          }}
        >
          <div className="relative min-w-0 flex-1 sm:w-56 sm:flex-none lg:w-64">
            <label htmlFor="trash-search" className="sr-only">Search Trash</label>
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
            <Input id="trash-search" value={searchValue} onChange={(event) => setSearchValue(event.target.value)} maxLength={120} placeholder="Search Trash" className="pl-9" />
          </div>
          <Button type="submit" variant="outline" size="md" className="shrink-0"><Search className="size-4" aria-hidden="true" />Search</Button>
        </form>
        <DropdownMenu>
          <DropdownMenuTrigger asChild><Button variant="outline" size="sm" className="shrink-0"><Filter className="size-4" />{filterLabel(resourceType)}<ChevronDown className="size-3.5" /></Button></DropdownMenuTrigger>
          <DropdownMenuContent align="start">
            <DropdownMenuLabel>Resource type</DropdownMenuLabel><DropdownMenuSeparator />
            {(['all', 'client', 'matter', 'document'] as TrashResourceFilter[]).map((option) => (
              <DropdownMenuCheckboxItem key={option} checked={resourceType === option} onCheckedChange={() => chooseType(option)}>{filterLabel(option)}</DropdownMenuCheckboxItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
        <div className="ml-auto flex min-h-8 items-center gap-2 text-xs text-[var(--text-muted)]" aria-live="polite">
          {isPending ? <><Loader2 className="size-3.5 animate-spin motion-reduce:animate-none" aria-hidden="true" />Updating Trash</> : <><HardDrive className="size-3.5" aria-hidden="true" />{formatBytes(data.totalStorageBytes)} in Trash</>}
        </div>
      </div>
      <div className="min-h-0 flex-1 overflow-hidden">
        <div className="hidden h-full min-h-0 md:flex">
          <section aria-label="Trash groups" className={cn('custom-scrollbar min-w-0 flex-1 overflow-y-auto overscroll-contain', selectedId && 'hidden xl:block')}>
            <OperationCollection operations={data.operations} selectedId={selectedId} timeZone={data.timeZone} filtered={filtered} onSelect={(id) => navigate({ selected: id })} />
          </section>
          {data.selectedOperation && <DetailPanel operation={data.selectedOperation} timeZone={data.timeZone} onClose={() => navigate({ selected: null })} />}
        </div>
        <div className="h-full overflow-hidden md:hidden">
          {data.selectedOperation ? (
            <DetailPanel operation={data.selectedOperation} timeZone={data.timeZone} mobile onClose={() => navigate({ selected: null })} />
          ) : (
            <section aria-label="Trash groups" className="custom-scrollbar h-full overflow-y-auto overscroll-contain">
              <OperationCollection operations={data.operations} selectedId={selectedId} timeZone={data.timeZone} filtered={filtered} onSelect={(id) => navigate({ selected: id })} />
            </section>
          )}
        </div>
      </div>
    </div>
  )
}
