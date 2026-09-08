'use client'

import type { ReactNode } from 'react'
import { unstable_catchError, type ErrorInfo } from 'next/error'

import { Button } from '@/components/ui/button'
import { type MatterSectionId, MATTER_SECTION_LABELS } from '@/lib/matters/workspace-route'

function MatterSectionErrorFallback(
  { section }: { section: MatterSectionId },
  { unstable_retry }: ErrorInfo,
) {
  const label = MATTER_SECTION_LABELS[section]
  return (
    <section
      className="flex min-h-64 flex-col items-center justify-center gap-3 border border-[var(--border)] bg-[var(--surface)] p-6 text-center"
      aria-labelledby="matter-section-error-title"
    >
      <h2 id="matter-section-error-title" className="text-lg font-semibold text-[var(--text-primary)]">
        {label} could not be loaded
      </h2>
      <p className="max-w-md text-sm text-[var(--text-secondary)]">
        The rest of this matter is still available. Retry this section, or choose another section above.
      </p>
      <Button type="button" variant="secondary" onClick={() => unstable_retry()}>
        Retry {label}
      </Button>
    </section>
  )
}

const MatterSectionErrorBoundary = unstable_catchError(MatterSectionErrorFallback)

export function MatterSectionBoundary({ children, section }: { children: ReactNode; section: MatterSectionId }) {
  return <MatterSectionErrorBoundary key={section} section={section}>{children}</MatterSectionErrorBoundary>
}
