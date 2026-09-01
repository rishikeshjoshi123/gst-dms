import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'

export default function TasksLoading() {
  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]" aria-busy="true">
      <p className="sr-only">Loading tasks…</p>
      <div className="grid shrink-0 gap-2 border-b border-[var(--border-subtle)] p-3 sm:grid-cols-[minmax(180px,320px)_8rem_8rem_1fr]"><Skeleton className="h-9 w-full" /><Skeleton className="h-9 w-full" /><Skeleton className="h-9 w-full" /><Skeleton className="hidden h-3 w-16 justify-self-end sm:block" /></div>
      <div className="min-h-0 flex-1 overflow-hidden">
        <div className="hidden h-full lg:block"><Table className="table-fixed"><TableCaption>Loading tasks.</TableCaption><colgroup><col className="w-[46%]" /><col className="w-[19%]" /><col className="w-[18%]" /><col className="w-[17%]" /></colgroup><TableHeader><TableRow><TableHead>Task</TableHead><TableHead>Assignee</TableHead><TableHead>Due</TableHead><TableHead>Status</TableHead></TableRow></TableHeader><TableBody>{[1, 2, 3, 4, 5].map((row) => <TableRow key={row} aria-hidden="true"><TableCell><Skeleton className="h-3.5 w-4/5" /><Skeleton className="mt-2 h-3 w-3/5" /></TableCell><TableCell><Skeleton className="h-3.5 w-24" /></TableCell><TableCell><Skeleton className="h-3.5 w-24" /></TableCell><TableCell><Skeleton className="h-6 w-28" /></TableCell></TableRow>)}</TableBody></Table></div>
        <div className="lg:hidden">{[1, 2, 3, 4, 5].map((row) => <div key={row} className="min-h-[92px] border-b border-[var(--border-subtle)] p-3" aria-hidden="true"><Skeleton className="h-3.5 w-4/5" /><Skeleton className="mt-2 h-3 w-3/5" /><Skeleton className="mt-3 h-3 w-1/2" /></div>)}</div>
      </div>
    </div>
  )
}
