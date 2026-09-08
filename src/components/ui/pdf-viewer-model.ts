export const PDF_PAGE_RENDER_RADIUS = 2
export const PDF_THUMBNAIL_RENDER_RADIUS = 2
export const DEFAULT_PDF_PAGE_SIZE = { width: 612, height: 792 }
export const PDF_SEARCH_BATCH_SIZE = 25

export function clampPdfPage(page: number, numPages?: number) {
  const integerPage = Number.isFinite(page) ? Math.trunc(page) : 1
  const lowerBounded = Math.max(1, integerPage)
  return numPages ? Math.min(numPages, lowerBounded) : lowerBounded
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
