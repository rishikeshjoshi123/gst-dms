import { EncryptedPDFError, PDFDocument } from 'pdf-lib'

export type ValidationOutcome = 'ready' | 'invalid_pdf' | 'encrypted_pdf' | 'storage_missing' | 'validation_failed'

export function safeValidationOutcome(error: unknown): ValidationOutcome {
  // pdf-lib's ES5 error factory returns an Error instance rather than preserving
  // `instanceof`, so recognize its stable class name/message at this boundary.
  if (error instanceof EncryptedPDFError || (error instanceof Error && (error.name === 'EncryptedPDFError' || /encrypted/i.test(error.message)))) return 'encrypted_pdf'
  return 'invalid_pdf'
}

export async function validatePdfBytes(bytes: Uint8Array, expectedBytes: number): Promise<{ outcome: ValidationOutcome; pageCount: number | null }> {
  if (bytes.byteLength !== expectedBytes) return { outcome: 'validation_failed', pageCount: null }
  try {
    const pdf = await PDFDocument.load(bytes, { ignoreEncryption: false, updateMetadata: false })
    const pageCount = pdf.getPageCount()
    return pageCount > 0 ? { outcome: 'ready', pageCount } : { outcome: 'invalid_pdf', pageCount: null }
  } catch (error) {
    return { outcome: safeValidationOutcome(error), pageCount: null }
  }
}
