import type { PdfSourceAccessFailureCode } from '@/lib/pdf-source-access'

export const PDF_PAGE_RENDER_RADIUS = 2
export const PDF_THUMBNAIL_RENDER_RADIUS = 2
export const DEFAULT_PDF_PAGE_SIZE = { width: 612, height: 792 }
export const PDF_SEARCH_BATCH_SIZE = 25

export type PdfSourceFailure = 'encrypted' | 'malformed' | 'missing' | 'unavailable' | 'render_failed'

export function pdfSourceFailureFromAccessCode(code: PdfSourceAccessFailureCode): PdfSourceFailure {
  return code === 'source_unavailable' ? 'missing' : 'unavailable'
}

export async function retryPdfSourceAccess({
  currentUrl,
  requestFreshUrl,
  refreshRoute,
}: {
  currentUrl: string | null
  requestFreshUrl?: () => Promise<string | null>
  refreshRoute: () => void
}) {
  if (requestFreshUrl) return requestFreshUrl()
  refreshRoute()
  return currentUrl
}

export function classifyPdfSourceFailure(error: unknown): PdfSourceFailure | null {
  if (!error || typeof error !== 'object') return 'render_failed'
  const name = 'name' in error && typeof error.name === 'string' ? error.name : ''
  if (name === 'AbortException' || name === 'RenderingCancelledException') return null
  if (name === 'PasswordException') return 'encrypted'
  if (name === 'InvalidPDFException' || name === 'FormatError') return 'malformed'
  if (name === 'ResponseException') return 'unavailable'
  return 'render_failed'
}

export function pdfSourceFailureCopy(kind: PdfSourceFailure) {
  switch (kind) {
    case 'encrypted':
      return {
        title: 'Password-protected PDF',
        detail: 'This source cannot be opened here. Upload an unencrypted PDF copy to make it viewable.',
        retryable: false,
        retryLabel: null,
      }
    case 'malformed':
      return {
        title: 'Unreadable PDF',
        detail: 'This file is not a valid readable PDF. Upload a valid PDF copy to continue.',
        retryable: false,
        retryLabel: null,
      }
    case 'missing':
      return {
        title: 'PDF file unavailable',
        detail: 'This stored PDF is not available. Return to the document record or contact an administrator if the source should be restored.',
        retryable: false,
        retryLabel: null,
      }
    case 'unavailable':
      return {
        title: 'PDF access needs refreshing',
        detail: 'The secure view link may have expired, or the source could not be retrieved. Refresh access and try again.',
        retryable: true,
        retryLabel: 'Refresh PDF access',
      }
    case 'render_failed':
      return {
        title: 'PDF could not be opened',
        detail: 'The viewer could not open this PDF. Try loading it again.',
        retryable: true,
        retryLabel: 'Retry PDF',
      }
  }
}

export function clampPdfPage(page: number, numPages?: number) {
  const integerPage = Number.isFinite(page) ? Math.trunc(page) : 1
  const lowerBounded = Math.max(1, integerPage)
  return numPages ? Math.min(numPages, lowerBounded) : lowerBounded
}

export function createPdfQuotationSelection(
  source: { documentId: string; documentVersionId: string },
  text: string,
  pageNumber: number,
  numPages: number,
) {
  const excerpt = text.trim()
  if (!source.documentId || !source.documentVersionId || !excerpt || !Number.isSafeInteger(pageNumber)
    || pageNumber < 1 || pageNumber > numPages) return null
  return { ...source, text: excerpt, pageNumber }
}

export function isPdfSourceRequestCurrent(
  request: { generation: number; sourceIdentity: string | null },
  current: { generation: number; sourceIdentity: string | null },
) {
  return request.generation === current.generation && request.sourceIdentity === current.sourceIdentity
}

export function isPdfPageInRenderWindow(page: number, currentPage: number) {
  return Math.abs(page - currentPage) <= PDF_PAGE_RENDER_RADIUS
}

export function isPdfThumbnailInRenderWindow(page: number, currentPage: number) {
  return Math.abs(page - currentPage) <= PDF_THUMBNAIL_RENDER_RADIUS
}

export function pdfThumbnailPages(currentPage: number, numPages: number) {
  const current = clampPdfPage(currentPage, numPages)
  const start = Math.max(1, current - PDF_THUMBNAIL_RENDER_RADIUS)
  const end = Math.min(numPages, current + PDF_THUMBNAIL_RENDER_RADIUS)
  return Array.from({ length: Math.max(0, end - start + 1) }, (_, index) => start + index)
}

export function pdfPageHeight({
  sourceSize = DEFAULT_PDF_PAGE_SIZE,
  rotation,
  fitWidth,
  pageWidth,
  scale,
}: {
  sourceSize?: { width: number; height: number }
  rotation: number
  fitWidth: boolean
  pageWidth?: number
  scale: number
}) {
  const rotated = rotation % 180 !== 0
  const width = rotated ? sourceSize.height : sourceSize.width
  const height = rotated ? sourceSize.width : sourceSize.height
  if (fitWidth && pageWidth) return Math.max(1, pageWidth * (height / width))
  return Math.max(1, height * scale)
}

export function pdfFitPageScale({
  sourceSize = DEFAULT_PDF_PAGE_SIZE,
  rotation,
  viewportWidth,
  viewportHeight,
}: {
  sourceSize?: { width: number; height: number }
  rotation: number
  viewportWidth?: number
  viewportHeight?: number
}) {
  const rotated = rotation % 180 !== 0
  const width = rotated ? sourceSize.height : sourceSize.width
  const height = rotated ? sourceSize.width : sourceSize.height
  if (!viewportWidth || !viewportHeight) return 1
  return Math.max(0.1, Math.min(viewportWidth / width, viewportHeight / height))
}

export function normalizePdfSearchQuery(value: string) {
  return value.trim().replace(/\s+/g, ' ').slice(0, 100)
}

export function nextPdfSearchBatch(searchedPages: number, numPages: number) {
  const start = Math.min(numPages + 1, Math.max(1, Math.trunc(searchedPages) + 1))
  const end = Math.min(numPages, start + PDF_SEARCH_BATCH_SIZE - 1)
  return { start, end, complete: start > numPages }
}

function escapeHtml(value: string) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
}

export function highlightPdfText(value: string, query: string) {
  const normalizedQuery = normalizePdfSearchQuery(query)
  if (!normalizedQuery) return escapeHtml(value)
  const expression = new RegExp(normalizedQuery.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'giu')
  let output = ''
  let offset = 0
  for (const match of value.matchAll(expression)) {
    const index = match.index ?? 0
    output += escapeHtml(value.slice(offset, index))
    output += `<mark style="background:var(--warning-muted);color:inherit">${escapeHtml(match[0])}</mark>`
    offset = index + match[0].length
  }
  return output + escapeHtml(value.slice(offset))
}
