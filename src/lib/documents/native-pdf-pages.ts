import { DOMMatrix, ImageData, Path2D } from '@napi-rs/canvas'

export const NATIVE_PAGE_QUALITY_POLICY_VERSION = 'native-pdf-quality-v1'

export type PageWordAnchor = {
  text: string
  x: number
  y: number
  width: number
  height: number
}

export type NativePdfPage = {
  pageNumber: number
  text: string
  words: PageWordAnchor[]
  imageOperationCount: number
  pageArea: number
}

export type NativePageQuality = {
  accepted: boolean
  reasons: string[]
}

type PdfTextItem = {
  str: string
  transform: number[]
  width: number
  height: number
  hasEOL: boolean
}

type PdfViewport = {
  width: number
  height: number
  convertToViewportPoint(x: number, y: number): number[]
}

type PdfJsModule = typeof import('pdfjs-dist/legacy/build/pdf.mjs')

let pdfJsModule: Promise<PdfJsModule> | null = null

async function loadPdfJs(): Promise<PdfJsModule> {
  // pdfjs-dist v5 expects DOMMatrix in Node. react-pdf already brings the
  // compatible canvas runtime; make it explicit before dynamically loading
  // the parser so the Trigger worker does not depend on a browser global.
  if (!globalThis.DOMMatrix) globalThis.DOMMatrix = DOMMatrix as unknown as typeof globalThis.DOMMatrix
  if (!globalThis.ImageData) globalThis.ImageData = ImageData as unknown as typeof globalThis.ImageData
  if (!globalThis.Path2D) globalThis.Path2D = Path2D as unknown as typeof globalThis.Path2D
  pdfJsModule ??= import('pdfjs-dist/legacy/build/pdf.mjs')
  return pdfJsModule
}

function isPdfTextItem(value: unknown): value is PdfTextItem {
  if (!value || typeof value !== 'object') return false
  const item = value as Partial<PdfTextItem>
  return typeof item.str === 'string'
    && Array.isArray(item.transform)
    && item.transform.length >= 6
    && typeof item.width === 'number'
    && typeof item.height === 'number'
}

function boundedNumber(value: number): number {
  return Math.max(0, Math.min(1, Number(value.toFixed(6))))
}

export function nativeTextWordAnchors(item: PdfTextItem, viewport: PdfViewport): PageWordAnchor[] {
  const value = item.str.trim()
  if (!value || /[\u0000-\u001f\u007f]/.test(value)) return []

  const words = [...value.matchAll(/\S+/gu)]
  if (words.length === 0) return []

  const [a, b, c, d, x, baselineY] = item.transform
  const itemWidth = Math.abs(item.width)
  const itemHeight = Math.abs(item.height || a || d || 0)
  const baselineScale = Math.hypot(a, b)
  const crossScale = Math.hypot(c, d)
  if (!Number.isFinite(x) || !Number.isFinite(baselineY) || !Number.isFinite(itemWidth) || !Number.isFinite(itemHeight)
    || !Number.isFinite(baselineScale) || !Number.isFinite(crossScale) || baselineScale <= 0 || crossScale <= 0
    || viewport.width <= 0 || viewport.height <= 0) return []

  // `width` is expressed in transformed display units. Build each word's
  // source-space quadrilateral along the text item's actual transformed
  // baseline, then map its four corners into top-left viewport coordinates.
  // Splitting a rotated bounding box horizontally would produce vertical
  // slivers and incorrect word anchors.
  const baseline = { x: (itemWidth * a) / baselineScale, y: (itemWidth * b) / baselineScale }
  const cross = { x: (itemHeight * c) / crossScale, y: (itemHeight * d) / crossScale }

  return words.flatMap((match) => {
    const text = match[0]
    const start = match.index ?? 0
    const end = start + text.length
    const startPoint = {
      x: x + (baseline.x * start) / value.length,
      y: baselineY + (baseline.y * start) / value.length,
    }
    const endPoint = {
      x: x + (baseline.x * end) / value.length,
      y: baselineY + (baseline.y * end) / value.length,
    }
    const corners = [
      viewport.convertToViewportPoint(startPoint.x, startPoint.y),
      viewport.convertToViewportPoint(endPoint.x, endPoint.y),
      viewport.convertToViewportPoint(endPoint.x + cross.x, endPoint.y + cross.y),
      viewport.convertToViewportPoint(startPoint.x + cross.x, startPoint.y + cross.y),
    ]
    const xCoordinates = corners.map(([pointX]) => pointX)
    const yCoordinates = corners.map(([, pointY]) => pointY)
    const minX = Math.min(...xCoordinates)
    const maxX = Math.max(...xCoordinates)
    const minY = Math.min(...yCoordinates)
    const maxY = Math.max(...yCoordinates)
    const word = {
      text,
      x: boundedNumber(minX / viewport.width),
      y: boundedNumber(minY / viewport.height),
      width: boundedNumber((maxX - minX) / viewport.width),
      height: boundedNumber((maxY - minY) / viewport.height),
    }
    return word.width > 0 && word.height > 0 ? [word] : []
  })
}

function pageText(items: PdfTextItem[]): string {
  let text = ''
  let lastX: number | null = null
  let lastY: number | null = null

  for (const item of items) {
    if (!item.str) continue
    const x = item.transform[4] ?? 0
    const y = item.transform[5] ?? 0
    const needsSpace = text.length > 0
      && !/\s$/u.test(text)
      && !/^\s/u.test(item.str)
      && (item.hasEOL || lastY === null || Math.abs(y - lastY) > Math.max(2, Math.abs(item.height) * 0.6) || (lastX !== null && x > lastX + 1))
    text += `${needsSpace ? ' ' : ''}${item.str}`
    lastX = x + Math.abs(item.width)
    lastY = y
  }
  return text.trim()
}

export function assessNativePageQuality(page: Pick<NativePdfPage, 'text' | 'words' | 'imageOperationCount' | 'pageArea'>): NativePageQuality {
  const reasons: string[] = []
  const text = page.text
  const meaningfulCharacters = [...text].filter((character) => /[^\s]/u.test(character)).length
  const density = page.pageArea > 0 ? meaningfulCharacters / page.pageArea : 0

  if (meaningfulCharacters < 24 || page.words.length < 4) reasons.push('sparse_text')
  if (/\ufffd/u.test(text)) reasons.push('replacement_character')
  if (/[\u0000-\u001f\u007f]/u.test(text)) reasons.push('broken_control_character')
  if (density > 0 && density < 0.00004) reasons.push('implausible_text_density')
  if (text.length > 8000) reasons.push('artifact_text_limit')
  if (page.words.length > 2000) reasons.push('artifact_anchor_limit')
  // A page with bitmap drawing operations and little text is commonly a scan
  // with a misleading or incomplete text layer. Route it conservatively.
  if (page.imageOperationCount > 0 && meaningfulCharacters < 1000) reasons.push('suspicious_image_mixed_page')

  return { accepted: reasons.length === 0, reasons }
}

export async function extractNativePdfPages(pdfBytes: Buffer): Promise<NativePdfPage[]> {
  const { OPS, getDocument } = await loadPdfJs()
  const loadingTask = getDocument({
    data: new Uint8Array(pdfBytes),
    disableFontFace: true,
    isEvalSupported: false,
    useSystemFonts: true,
    stopAtErrors: false,
  })
  const document = await loadingTask.promise
  try {
    const pages: NativePdfPage[] = []
    for (let pageNumber = 1; pageNumber <= document.numPages; pageNumber += 1) {
      const page = await document.getPage(pageNumber)
      const viewport = page.getViewport({ scale: 1 })
      const content = await page.getTextContent({ disableNormalization: true })
      const items = content.items.filter(isPdfTextItem) as unknown as PdfTextItem[]
      const operatorList = await page.getOperatorList()
      const imageOperationCount = operatorList.fnArray.filter((operation) => (
        operation === OPS.paintImageXObject
        || operation === OPS.paintImageMaskXObject
        || operation === OPS.paintSolidColorImageMask
      )).length
      pages.push({
        pageNumber,
        text: pageText(items),
        words: items.flatMap((item) => nativeTextWordAnchors(item, viewport)),
        imageOperationCount,
        pageArea: viewport.width * viewport.height,
      })
    }
    return pages
  } finally {
    await document.destroy()
  }
}
