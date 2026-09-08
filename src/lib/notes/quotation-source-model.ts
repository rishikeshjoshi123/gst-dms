import { canonicalDocumentPath } from '@/lib/canonical-document-route'

export type QuotationLocator = {
  document_id: string
  document_version_id: string
  page_number: number
  excerpt: string
  version_number: number
  is_current: boolean
  source_available: boolean
}

export function quotationSourcePresentation(note: {
  quote?: string | null
  page_number?: number | null
  quotation_locator?: QuotationLocator | null
}, options: { matterId?: string; readOnly?: boolean } = {}) {
  const locator = note.quotation_locator
  const excerpt = locator?.excerpt ?? note.quote ?? null
  if (!excerpt) return { kind: 'none' as const, excerpt: null, href: null }
  if (!locator) return {
    kind: 'unverified' as const,
    excerpt,
    href: null,
    pageNumber: note.page_number ?? null,
  }
  return {
    kind: locator.source_available ? 'exact' as const : 'unavailable' as const,
    excerpt,
    pageNumber: locator.page_number,
    versionNumber: locator.version_number,
    historical: !locator.is_current,
    href: locator.source_available ? canonicalDocumentPath(locator.document_id, {
      version: locator.document_version_id,
      page: String(locator.page_number),
      ...(options.readOnly && options.matterId ? { matterId: options.matterId } : {}),
    }) : null,
  }
}
