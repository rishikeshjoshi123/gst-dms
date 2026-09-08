export type PdfSourceAccessFailureCode = 'not_authenticated' | 'source_unavailable' | 'access_temporary'

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
