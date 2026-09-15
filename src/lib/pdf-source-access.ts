export type PdfSourceAccessFailureCode = 'not_authenticated' | 'source_unavailable' | 'access_temporary'

/** Only Storage's typed 404 proves missing bytes (local API may carry it under HTTP 400). */
export function pdfStorageFailureCode(error: unknown): Exclude<PdfSourceAccessFailureCode, 'not_authenticated'> {
  if (error && typeof error === 'object') {
    const candidate = error as { status?: unknown; statusCode?: unknown }
    if (candidate.status === 404 || candidate.statusCode === '404' || candidate.statusCode === 404) {
      return 'source_unavailable'
    }
  }
  return 'access_temporary'
}

/** A trusted exact signed-source HEAD must succeed before releasing its URL. */
export function pdfSignedHeadFailureCode(status: number): Exclude<PdfSourceAccessFailureCode, 'not_authenticated'> | null {
  if (status >= 200 && status < 300) return null
  return status === 404 ? 'source_unavailable' : 'access_temporary'
}

export function pdfSourceLookupFailureCode({
  lookupFailed,
  sourceAvailable,
}: {
  lookupFailed: boolean
  sourceAvailable: boolean
}): Exclude<PdfSourceAccessFailureCode, 'not_authenticated'> | null {
  if (lookupFailed) return 'access_temporary'
  return sourceAvailable ? null : 'source_unavailable'
}
