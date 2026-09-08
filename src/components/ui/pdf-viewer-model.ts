export const PDF_PAGE_RENDER_RADIUS = 2
export const DEFAULT_PDF_PAGE_SIZE = { width: 612, height: 792 }

export function clampPdfPage(page: number, numPages?: number) {
  const integerPage = Number.isFinite(page) ? Math.trunc(page) : 1
  const lowerBounded = Math.max(1, integerPage)
  return numPages ? Math.min(numPages, lowerBounded) : lowerBounded
}

export function isPdfPageInRenderWindow(page: number, currentPage: number) {
  return Math.abs(page - currentPage) <= PDF_PAGE_RENDER_RADIUS
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
