import Link from 'next/link'
import { ExternalLink, FileWarning } from 'lucide-react'

import { quotationSourcePresentation, type QuotationLocator } from '@/lib/notes/quotation-source-model'

type QuotationNote = {
  document_id?: string | null
  quote?: string | null
  page_number?: number | null
  quotation_locator?: QuotationLocator | null
}

export function QuotationSource({
  note,
  matterId,
  readOnly = false,
  className = '',
}: {
  note: QuotationNote
  matterId?: string
  readOnly?: boolean
  className?: string
}) {
  const locator = note.quotation_locator
  const presentation = quotationSourcePresentation(note, { matterId, readOnly })
  if (presentation.kind === 'none') return null

  return (
    <aside className={`space-y-2 border-l-4 border-[var(--warning)] bg-[var(--warning-muted)] p-3 text-sm ${className}`}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex min-w-0 items-center gap-2 text-xs font-semibold text-[var(--text-secondary)]">
          <FileWarning className="size-4 shrink-0" aria-hidden="true" />
          {locator ? (
            <span>
              Page {locator.page_number} · Version {locator.version_number}
              {!locator.is_current && ' · Historical source'}
            </span>
          ) : (
            <span>
              {note.page_number ? `Original page ${note.page_number} · ` : ''}Source location unverified
            </span>
          )}
        </div>
        {presentation.href ? (
          <Link
            href={presentation.href}
            className="touch-target inline-flex min-h-11 items-center justify-center gap-1.5 rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 text-xs font-medium text-[var(--text-primary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
          >
            <ExternalLink className="size-4" aria-hidden="true" />
            Open exact source
          </Link>
        ) : presentation.kind === 'unavailable' ? (
          <span className="text-xs font-medium text-[var(--text-secondary)]">Source unavailable</span>
        ) : null}
      </div>
      <blockquote className="break-words italic leading-relaxed text-[var(--text-primary)]">
        “{presentation.excerpt}”
      </blockquote>
    </aside>
  )
}
