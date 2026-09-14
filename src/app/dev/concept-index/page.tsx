import type { Metadata } from 'next'
import Link from 'next/link'
import { ArrowRight, BookOpen, ExternalLink, Layers3 } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { ThemeToggle } from '@/components/nav/ThemeToggle'

import { conceptCount, conceptGroups } from './concepts'

export const metadata: Metadata = {
  title: 'Concept Index',
  description: 'The ordered review catalogue for CaseChain product concepts.',
}

export default function ConceptIndexPage() {
  return (
    <main className="min-h-dvh overflow-x-hidden bg-[var(--bg)] text-[var(--text-primary)]">
      <header className="border-b border-[var(--border)] bg-[var(--surface)]">
        <div className="mx-auto flex w-full max-w-7xl flex-col gap-5 px-4 py-8 sm:px-6 sm:py-10 lg:px-8">
          <div className="flex items-center justify-between gap-4">
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant="outline">Developer review</Badge>
              <span className="text-caption text-[var(--text-muted)]">{conceptCount} concepts · fixture data only</span>
            </div>
            <ThemeToggle />
          </div>
          <div className="max-w-3xl">
            <p className="text-caption font-semibold uppercase tracking-[0.12em] text-[var(--primary)]">CaseChain product review</p>
            <h1 className="mt-2 text-page-title">Concept index</h1>
            <p className="mt-3 text-sm leading-6 text-[var(--text-secondary)] sm:text-base sm:leading-7">
              Review the concepts in this order to follow the product from organisation setup through legal work and final record retention. Each page is a local, non-production interface for discussing behavior and layout.
            </p>
          </div>
          <nav aria-label="Concept review phases" className="flex flex-wrap gap-x-5 gap-y-2 text-sm">
            {conceptGroups.map((group) => (
              <a key={group.id} href={`#${group.id}`} className="inline-flex min-h-11 items-center font-medium text-[var(--primary)] underline-offset-4 hover:underline focus-visible:rounded-[var(--radius-sm)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">
                {group.step} · {group.title}
              </a>
            ))}
          </nav>
        </div>
      </header>

      <div className="mx-auto w-full max-w-7xl px-4 py-7 sm:px-6 sm:py-9 lg:px-8">
        <div className="space-y-10">
          {conceptGroups.map((group) => (
            <section key={group.id} id={group.id} aria-labelledby={`${group.id}-heading`} className="scroll-mt-5">
              <div className="grid gap-4 border-b border-[var(--border)] pb-4 md:grid-cols-[5rem_minmax(0,1fr)]">
                <span className="font-mono text-sm font-semibold text-[var(--primary)]">{group.step}</span>
                <div>
                  <h2 id={`${group.id}-heading`} className="text-section-heading">{group.title}</h2>
                  <p className="mt-1 max-w-3xl text-sm leading-6 text-[var(--text-muted)]">{group.description}</p>
                </div>
              </div>

              <ol className="mt-4 grid gap-3 lg:grid-cols-2">
                {group.concepts.map((concept, conceptIndex) => (
                  <li key={concept.href}>
                    <Link
                      href={concept.href}
                      className="group flex min-h-full items-start gap-4 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4 outline-none transition-colors duration-[var(--duration-fast)] ease-[var(--ease-smooth)] hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] motion-reduce:transition-none sm:p-5"
                    >
                      <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] font-mono text-xs font-semibold text-[var(--primary)]" aria-hidden="true">
                        {group.step}.{conceptIndex + 1}
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="flex items-start justify-between gap-3">
                          <span className="text-sm font-semibold sm:text-base">{concept.title}</span>
                          <ArrowRight className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)] transition-transform duration-[var(--duration-fast)] group-hover:translate-x-0.5 motion-reduce:transition-none" aria-hidden="true" />
                        </span>
                        <span className="mt-2 block text-sm leading-6 text-[var(--text-secondary)]">{concept.description}</span>
                        <span className="mt-3 block border-t border-[var(--border-subtle)] pt-3 text-xs leading-5 text-[var(--text-muted)]">
                          <strong className="font-medium text-[var(--text-secondary)]">Review focus:</strong> {concept.reviewFocus}
                        </span>
                      </span>
                    </Link>
                  </li>
                ))}
              </ol>
            </section>
          ))}
        </div>

        <aside className="mt-10 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4 sm:flex sm:items-center sm:justify-between sm:gap-6 sm:p-5" aria-labelledby="reference-heading">
          <div className="flex items-start gap-3">
            <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] text-[var(--text-secondary)]" aria-hidden="true"><Layers3 className="size-4" /></span>
            <div>
              <h2 id="reference-heading" className="text-sm font-semibold">Supporting implementation reference</h2>
              <p className="mt-1 text-sm leading-6 text-[var(--text-muted)]">The Civic Ink gallery documents the shared tokens, components, and responsive patterns used by these concepts.</p>
            </div>
          </div>
          <Link href="/dev/design-system" className="mt-4 inline-flex min-h-11 shrink-0 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-4 text-sm font-medium outline-none hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] sm:mt-0">
            <BookOpen className="size-4" aria-hidden="true" />
            Open design system
            <ExternalLink className="size-3.5" aria-hidden="true" />
          </Link>
        </aside>
      </div>
    </main>
  )
}
