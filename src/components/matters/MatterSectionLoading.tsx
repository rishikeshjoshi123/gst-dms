import { MATTER_SECTION_LABELS, type MatterSectionId } from '@/lib/matters/workspace-route'

export function MatterSectionLoading({ section }: { section: MatterSectionId }) {
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
