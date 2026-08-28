import { createHash } from 'crypto'

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const PDF_SIGNATURE = Buffer.from('%PDF-')

export type StoredPdfObservation =
  | { ok: true; byteSize: number; sha256: string; detectedMime: 'application/pdf' }
  | { ok: false; byteSize: number }

/**
 * Derive finalisation facts from the object read back from private Storage.
 * Browser-declared MIME types and hashes are never used as lifecycle facts.
 */
export async function observeStoredPdf(blob: Blob): Promise<StoredPdfObservation> {
  const bytes = Buffer.from(await blob.arrayBuffer())

  if (bytes.length < PDF_SIGNATURE.length || !bytes.subarray(0, PDF_SIGNATURE.length).equals(PDF_SIGNATURE)) {
    return { ok: false, byteSize: bytes.length }
  }

  return {
    ok: true,
    byteSize: bytes.length,
    sha256: createHash('sha256').update(bytes).digest('hex'),
    detectedMime: 'application/pdf',
  }
}

export function uploadIdempotencyKey(value: FormDataEntryValue | null): string | null {
  return typeof value === 'string' && UUID_PATTERN.test(value) ? value : null
}

export function retainFailedUploads<T extends { idempotencyKey: string }>(uploads: readonly T[], failedKeys: ReadonlySet<string>) {
  return uploads.filter(({ idempotencyKey }) => failedKeys.has(idempotencyKey))
}
