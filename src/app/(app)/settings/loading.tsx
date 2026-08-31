import { Skeleton } from '@/components/ui/skeleton'

export default function SettingsLoading() {
  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-y-auto custom-scrollbar" aria-busy="true" aria-live="polite">
      <p className="sr-only">Loading organisation settings…</p>
      <div className="mx-auto w-full max-w-4xl space-y-4 pb-12">
        {[1, 2, 3].map((item) => (
          <div key={item} className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4">
            <div className="flex items-center gap-3 border-b border-[var(--border-subtle)] pb-3">
              <Skeleton className="size-9 shrink-0" />
              <div className="min-w-0 flex-1"><Skeleton className="h-4 w-40" /><Skeleton className="mt-2 h-3 w-3/5" /></div>
            </div>
            <div className="mt-4 grid gap-3 sm:grid-cols-[minmax(0,1fr)_18rem]">
              <div><Skeleton className="h-4 w-36" /><Skeleton className="mt-2 h-3 w-4/5" /></div>
              <Skeleton className="h-11 w-full" />
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
