import { Skeleton } from '@/components/ui/skeleton'
export default function ReviewLoading() {
  return <section className="flex min-h-0 flex-1 flex-col overflow-hidden"><h1 className="mb-3 text-page-title">Review</h1><p role="status" className="mb-3 text-sm">Loading Review…</p><div aria-hidden="true" className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)]"><div className="h-24 border-b border-[var(--border)] p-3"><Skeleton className="h-11 w-full" /></div>{Array.from({ length: 8 }, (_, index) => <div key={index} className="flex h-14 items-center gap-4 border-b border-[var(--border)] px-3"><Skeleton className="h-8 flex-1" /><Skeleton className="h-5 w-24" /></div>)}</div></section>
}
