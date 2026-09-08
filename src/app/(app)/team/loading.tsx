import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'

export default function Loading() {
  return (
    <div className="flex min-h-0 flex-1 flex-col" aria-busy="true" aria-label="Loading team members">
      <div className="flex flex-col gap-3 border-b border-[var(--border)] px-4 py-3 sm:flex-row">
        <div><Skeleton className="h-6 w-20" /><Skeleton className="mt-2 h-3 w-32" /></div>
        <Skeleton className="h-11 min-w-0 flex-1" />
      </div>
      <div className="grid grid-cols-1 gap-2 border-b border-[var(--border)] px-4 py-2 sm:grid-cols-[minmax(0,1fr)_minmax(0,10rem)_minmax(0,10rem)] sm:items-end">
        <Skeleton className="h-4 w-20" />
        <div><Skeleton className="mb-1 h-3 w-10" /><Skeleton className="h-11 w-full" /></div>
        <div><Skeleton className="mb-1 h-3 w-12" /><Skeleton className="h-11 w-full" /></div>
      </div>
      <div className="custom-scrollbar hidden min-h-0 flex-1 overflow-y-auto lg:block">
        <Table>
          <TableHeader sticky><TableRow><TableHead>Person</TableHead><TableHead>Role</TableHead><TableHead>Status</TableHead><TableHead>Joined</TableHead></TableRow></TableHeader>
          <TableBody>{Array.from({ length: 8 }, (_, index) => (
            <TableRow key={index} className="h-12">
              <TableCell className="py-0"><div className="flex h-12 items-center gap-3"><Skeleton className="h-8 w-8 shrink-0 rounded-full" /><div className="min-w-0"><Skeleton className="h-4 w-36" /><Skeleton className="mt-1 h-3 w-24" /></div></div></TableCell>
              <TableCell className="py-0"><Skeleton className="h-6 w-24" /></TableCell>
              <TableCell className="py-0"><Skeleton className="h-6 w-20" /></TableCell>
              <TableCell className="py-0"><Skeleton className="h-3 w-20" /></TableCell>
            </TableRow>
          ))}</TableBody>
        </Table>
      </div>
      <div className="custom-scrollbar min-h-0 flex-1 space-y-2 overflow-y-auto p-3 lg:hidden">{Array.from({ length: 5 }, (_, index) => (
        <div key={index} className="flex min-h-16 items-center gap-3 rounded-[var(--radius-md)] border border-[var(--border)] p-3"><Skeleton className="h-8 w-8 shrink-0 rounded-full" /><div className="min-w-0 flex-1"><Skeleton className="h-4 w-32" /><Skeleton className="mt-1 h-3 w-24" /><Skeleton className="mt-2 h-6 w-24" /></div><Skeleton className="h-6 w-20" /></div>
      ))}</div>
    </div>
  )
}
