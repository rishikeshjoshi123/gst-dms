import { MATTER_SECTION_LABELS, type MatterSectionId } from '@/lib/matters/workspace-route'

export function MatterSectionLoading({ section }: { section: MatterSectionId }) {
  if (section === 'timeline') {
    return (
      <div className="flex h-full min-h-64 flex-col gap-3 pt-2 lg:pt-3" aria-busy="true" aria-live="polite">
        <span className="sr-only">Loading {MATTER_SECTION_LABELS[section]}</span>
        <div className="flex min-h-14 shrink-0 items-center justify-between gap-3 border-b border-[var(--border)] bg-[var(--surface)] px-3 py-2">
          <div className="space-y-2"><div className="h-4 w-24 animate-pulse rounded-[var(--radius-sm)] bg-[var(--surface-hover)] motion-reduce:animate-none" /><div className="h-3 w-44 animate-pulse rounded-[var(--radius-sm)] bg-[var(--surface-hover)] motion-reduce:animate-none" /></div>
          <div className="h-11 w-24 animate-pulse rounded-[var(--radius-sm)] bg-[var(--surface-hover)] motion-reduce:animate-none" />
        </div>
        <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto border border-[var(--border)] bg-[var(--surface)]">
          <div className="hidden min-w-[900px] grid-cols-[10rem_minmax(16rem,1fr)_9rem_11rem_11rem_10rem] border-b border-[var(--border)] px-3 py-3 lg:grid">
            {[72, 96, 64, 112, 72, 88].map((width, index) => <div key={index} style={{ width }} className="h-3 animate-pulse rounded-[var(--radius-sm)] bg-[var(--surface-hover)] motion-reduce:animate-none" />)}
          </div>
          {[0, 1, 2, 3, 4].map((row) => <div key={row} className="border-b border-[var(--border)] p-3 last:border-0 lg:grid lg:min-h-14 lg:grid-cols-[10rem_minmax(16rem,1fr)_9rem_11rem_11rem_10rem] lg:items-center"><div className="h-4 w-24 animate-pulse rounded-[var(--radius-sm)] bg-[var(--surface-hover)] motion-reduce:animate-none" /><div className="mt-2 h-4 w-3/5 animate-pulse rounded-[var(--radius-sm)] bg-[var(--surface-hover)] motion-reduce:animate-none lg:mt-0" /><div className="mt-2 h-3 w-32 animate-pulse rounded-[var(--radius-sm)] bg-[var(--surface-hover)] motion-reduce:animate-none lg:mt-0 lg:w-16" /><div className="hidden h-3 w-24 animate-pulse rounded-[var(--radius-sm)] bg-[var(--surface-hover)] motion-reduce:animate-none lg:block" /><div className="hidden h-3 w-20 animate-pulse rounded-[var(--radius-sm)] bg-[var(--surface-hover)] motion-reduce:animate-none lg:block" /><div className="hidden h-3 w-24 animate-pulse rounded-[var(--radius-sm)] bg-[var(--surface-hover)] motion-reduce:animate-none lg:block" /></div>)}
        </div>
      </div>
    )
  }

  return (
    <div
      className="flex min-h-64 flex-col gap-4 border border-[var(--border)] bg-[var(--surface)] p-5"
      aria-busy="true"
      aria-live="polite"
    >
      <span className="sr-only">Loading {MATTER_SECTION_LABELS[section]}</span>
      <div className="h-11 w-full max-w-2xl animate-pulse rounded-[var(--radius-sm)] bg-[var(--surface-hover)] motion-reduce:animate-none" />
      <div className="grid flex-1 gap-3 sm:grid-cols-2">
        <div className="min-h-40 animate-pulse rounded-[var(--radius-md)] bg-[var(--surface-hover)] motion-reduce:animate-none" />
        <div className="min-h-40 animate-pulse rounded-[var(--radius-md)] bg-[var(--surface-hover)] motion-reduce:animate-none" />
      </div>
    </div>
  )
}
