import {
  ocrDocumentAiEnterprisePages,
  resolveDocumentAiOcrConfiguration,
} from './document-ai-enterprise-ocr'
import {
  assessNativePageQuality,
  extractNativePdfPages,
  NATIVE_PAGE_QUALITY_POLICY_VERSION,
  type PageWordAnchor,
} from './native-pdf-pages'
import type { CanonicalTableCell } from './source-verifier'

export type AcquiredPageText = {
  page_number: number
  text: string
  ocr_words: PageWordAnchor[] | null
  table_cells: CanonicalTableCell[]
  acquisition_method: 'native_pdf' | 'document_ai_ocr'
  quality_policy_version: typeof NATIVE_PAGE_QUALITY_POLICY_VERSION
  quality_reasons: string[]
  detected_languages: string[]
  ocr_processor_identifier: string | null
  ocr_processor_version: string | null
}

export type PageAcquisitionOutcome =
  | { kind: 'complete'; pages: AcquiredPageText[] }
  | { kind: 'not_indexable'; reason: 'native_unreadable' | 'page_count_mismatch' | 'ocr_environment_unavailable' | 'ocr_unreadable' }

export async function acquireDocumentPageText(
  pdfBytes: Buffer,
  expectedPageCount: number,
): Promise<PageAcquisitionOutcome> {
  let nativePages
  try {
    nativePages = await extractNativePdfPages(pdfBytes)
  } catch {
    return { kind: 'not_indexable', reason: 'native_unreadable' }
  }
  if (nativePages.length !== expectedPageCount) return { kind: 'not_indexable', reason: 'page_count_mismatch' }

  const nativeQuality = nativePages.map((page) => ({ page, quality: assessNativePageQuality(page) }))
  const rejected = nativeQuality.filter(({ quality }) => !quality.accepted)
  if (rejected.length === 0) {
    return {
      kind: 'complete',
      pages: nativeQuality.map(({ page, quality }) => ({
        page_number: page.pageNumber,
        text: page.text,
        ocr_words: page.words,
        table_cells: [],
        acquisition_method: 'native_pdf',
        quality_policy_version: NATIVE_PAGE_QUALITY_POLICY_VERSION,
        quality_reasons: quality.reasons,
        detected_languages: [],
        ocr_processor_identifier: null,
        ocr_processor_version: null,
      })),
    }
  }

  const configuration = resolveDocumentAiOcrConfiguration()
  if (!configuration) return { kind: 'not_indexable', reason: 'ocr_environment_unavailable' }
  const ocrPages = await ocrDocumentAiEnterprisePages(pdfBytes, rejected.map(({ page }) => page.pageNumber), configuration)
  if (!ocrPages) return { kind: 'not_indexable', reason: 'ocr_unreadable' }

  const pages = nativeQuality.map(({ page, quality }): AcquiredPageText | null => {
    if (quality.accepted) {
      return {
        page_number: page.pageNumber, text: page.text, ocr_words: page.words, table_cells: [],
        acquisition_method: 'native_pdf', quality_policy_version: NATIVE_PAGE_QUALITY_POLICY_VERSION,
        quality_reasons: quality.reasons, detected_languages: [],
        ocr_processor_identifier: null, ocr_processor_version: null,
      }
    }
    const ocr = ocrPages.get(page.pageNumber)
    if (!ocr) return null
    return {
      page_number: page.pageNumber, text: ocr.text, ocr_words: ocr.words.length > 0 ? ocr.words : null, table_cells: ocr.tableCells,
      acquisition_method: 'document_ai_ocr', quality_policy_version: NATIVE_PAGE_QUALITY_POLICY_VERSION,
      quality_reasons: quality.reasons, detected_languages: ocr.detectedLanguages,
      ocr_processor_identifier: ocr.processorId, ocr_processor_version: ocr.processorVersion,
    }
  })
  if (pages.some((page): page is null => page === null)) return { kind: 'not_indexable', reason: 'ocr_unreadable' }
  return { kind: 'complete', pages: pages as AcquiredPageText[] }
}
