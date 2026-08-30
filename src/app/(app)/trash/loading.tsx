import { Filter, HardDrive, Search } from 'lucide-react'

import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'

function LoadingRow() {
  return (
    <TableRow aria-hidden="true">
      <TableCell><div className="flex min-h-11 items-center gap-3"><Skeleton className="size-9 shrink-0" /><div className="min-w-0 flex-1"><Skeleton className="h-3.5 w-4/5 max-w-72" /><Skeleton className="mt-2 h-3 w-3/5 max-w-56" /></div></div></TableCell>
      <TableCell><Skeleton className="h-3.5 w-28" /><Skeleton className="mt-2 h-3 w-36" /></TableCell>
      <TableCell><Skeleton className="h-3 w-28" /><Skeleton className="mt-2 h-3 w-16" /></TableCell>
      <TableCell><Skeleton className="ml-auto h-8 w-24" /></TableCell>
    </TableRow>
  )
}

function MobileLoadingCard() {
  return (
    <div className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4" aria-hidden="true">
      <div className="flex gap-3"><Skeleton className="size-9 shrink-0" /><div className="min-w-0 flex-1"><Skeleton className="h-3 w-16" /><Skeleton className="mt-2 h-3.5 w-4/5" /><Skeleton className="mt-2 h-3 w-3/5" /></div></div>
      <div className="mt-3 grid grid-cols-2 gap-3 border-t border-[var(--border-subtle)] pt-3"><div><Skeleton className="h-3 w-12" /><Skeleton className="mt-2 h-3 w-4/5" /></div><div><Skeleton className="h-3 w-12" /><Skeleton className="mt-2 h-3 w-3/5" /></div></div>
    </div>
  )
}

export default function TrashLoading() {
  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]" aria-busy="true" aria-live="polite">
      <p className="sr-only">Loading Trash groups…</p>
      <div className="flex min-h-14 shrink-0 flex-wrap items-center gap-2 border-b border-[var(--border-subtle)] px-3 py-1.5 sm:flex-nowrap sm:px-4" aria-hidden="true">
        <div className="flex w-full min-w-0 items-center gap-2 sm:w-auto">
          <div className="relative h-10 min-w-0 flex-1 rounded-[var(--radius-sm)] border border-[var(--border-strong)] sm:w-56 sm:flex-none lg:w-64"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" /><Skeleton className="absolute left-9 top-1/2 h-3 w-28 -translate-y-1/2" /></div>
          <div className="flex h-9 w-20 shrink-0 items-center justify-center rounded-[var(--radius-sm)] border border-[var(--border-strong)]"><Skeleton className="h-3 w-11" /></div>
        </div>
        <div className="flex h-8 w-28 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3"><Filter className="size-4 text-[var(--text-muted)]" /><Skeleton className="h-3 w-14" /></div>
        <div className="ml-auto flex items-center gap-2"><HardDrive className="size-3.5 text-[var(--text-muted)]" /><Skeleton className="h-3 w-24" /></div>
      </div>
      <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain">
        <div className="hidden min-w-[720px] lg:block">
          <Table className="table-fixed">
            <TableCaption>Loading Trash groups.</TableCaption>
            <colgroup><col className="w-[48%]" /><col className="w-[25%]" /><col className="w-[18%]" /><col className="w-[120px]" /></colgroup>
            <TableHeader sticky><TableRow><TableHead>Item</TableHead><TableHead>Deleted</TableHead><TableHead>Included</TableHead><TableHead><span className="sr-only">Loading details actions</span></TableHead></TableRow></TableHeader>
            <TableBody>{[1, 2, 3, 4].map((row) => <LoadingRow key={row} />)}</TableBody>
          </Table>
        </div>
        <div className="space-y-3 p-3 lg:hidden">{[1, 2, 3].map((row) => <MobileLoadingCard key={row} />)}</div>
      </div>
    </div>
  )
}
