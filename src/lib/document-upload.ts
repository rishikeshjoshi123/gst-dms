import { createHash } from 'crypto'

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const PDF_SIGNATURE = Buffer.from('%PDF-')

export type StoredPdfObservation =
  | { ok: true; byteSize: number; sha256: string; detectedMime: 'application/pdf' }
  | { ok: false; byteSize: number }

export type UploadFailureResolution = 'retry' | 'terminal' | 'duplicate'

export type UploadFailureResult = {
  error: string
  retryable: boolean
  resolution: UploadFailureResolution
  /** Keep this key when retrying so the reservation can be resumed safely. */
  retainIdempotencyKey: boolean
}

/**
 * A fail command owns cleanup only after it has durably terminalised the
 * session. `not_available` is intentionally excluded: another request may
 * have finalised the same asset between the browser's read and this command.
 */
export function ownsTerminalUploadCleanup(code: string | null | undefined) {
  return code === 'ok'
}

/** A storage tombstone changes quota accounting only when the RPC confirms it. */
export function storageDeletionWasRecorded(code: string | null | undefined) {
  return code === 'deleted' || code === 'already_deleted'
}

export function uploadFailureResult(
  error: string,
  resolution: UploadFailureResolution = 'retry',
): UploadFailureResult {
  return {
    error,
    retryable: resolution === 'retry',
    resolution,
    retainIdempotencyKey: resolution === 'retry',
  }
}

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
