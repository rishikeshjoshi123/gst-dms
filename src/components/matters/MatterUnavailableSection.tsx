import type { ReactNode } from 'react'

export function MatterUnavailableSection({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex min-h-64 flex-col items-center justify-center gap-2 border border-[var(--border)] bg-[var(--surface)] p-6 text-center">
      <h2 className="text-lg font-semibold text-[var(--text-primary)]">{title}</h2>
      <p className="max-w-lg text-sm leading-6 text-[var(--text-secondary)]">{children}</p>
    </section>
  )
}
