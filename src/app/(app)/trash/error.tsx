'use client'

import { CircleAlert } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'

export default function TrashError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Organisation utilities' }, { label: 'Trash' }]} />
      <div className="grid min-h-0 flex-1 place-items-center overflow-y-auto p-6 text-center">
        <div>
          <CircleAlert className="mx-auto size-8 text-[var(--danger)]" aria-hidden="true" />
          <h1 className="mt-3 text-section-heading">Trash could not be displayed</h1>
          <p className="mx-auto mt-2 max-w-md text-sm text-[var(--text-muted)]">The read-only list did not load. Try again without changing anything in Trash.</p>
          <Button variant="outline" className="mt-4" onClick={reset}>Try again</Button>
        </div>
      </div>
    </div>
  )
}
