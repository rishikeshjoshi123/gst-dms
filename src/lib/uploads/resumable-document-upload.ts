'use client'

import * as tus from 'tus-js-client'

import { cancelDocumentUpload, finalizeDocumentUpload, reserveDocumentUpload } from '@/lib/actions/document'
import {
  abortThenCancel,
  clearDocumentUploadRecovery,
  prepareDocumentUploadRecovery,
  startResumableTransfer,
  writeDocumentUploadRecovery,
} from '@/lib/uploads/document-upload-recovery'

export const DOCUMENT_UPLOAD_CHUNK_BYTES = 6 * 1024 * 1024

type StoredUpload = {
  size: number | null
  metadata: Record<string, string>
  creationTime: string
  urlStorageKey: string
  uploadUrl: string | null
  parallelUploadUrls: string[] | null
}

export type DocumentUploadControl = { cancel: () => Promise<void> }

type TransferOutcome =
  | { kind: 'transferred' }
  | { kind: 'cancelled'; result: Awaited<ReturnType<typeof cancelDocumentUpload>> }
  | { kind: 'error'; message: string }

class SessionUploadUrlStorage {
  private prefix = 'casechain-tus::'

  async findAllUploads() { return this.findEntries(this.prefix) }
  async findUploadsByFingerprint(fingerprint: string) { return this.findEntries(`${this.prefix}${fingerprint}::`) }
  async removeUpload(urlStorageKey: string) { sessionStorage.removeItem(urlStorageKey) }

  async addUpload(fingerprint: string, upload: StoredUpload) {
    const key = `${this.prefix}${fingerprint}::${crypto.randomUUID()}`
    // TUS needs its opaque resumable URL, not CaseChain's raw object metadata.
    // Tokens, PDF bytes, bucket names, and object paths never enter storage.
    sessionStorage.setItem(key, JSON.stringify({ ...upload, metadata: {} }))
    return key
  }

  private findEntries(prefix: string) {
    const uploads: StoredUpload[] = []
    for (let index = 0; index < sessionStorage.length; index++) {
      const key = sessionStorage.key(index)
      if (!key?.startsWith(prefix)) continue
      try {
        const upload = JSON.parse(sessionStorage.getItem(key) ?? '') as StoredUpload
        uploads.push({ ...upload, metadata: {}, urlStorageKey: key })
      } catch {
        sessionStorage.removeItem(key)
      }
    }
    return uploads
  }
}

export function documentUploadIdempotencyKey(file: File, intendedMatterId: string | null, attachmentDocumentId?: string) {
  return prepareDocumentUploadRecovery(sessionStorage, file, intendedMatterId, () => crypto.randomUUID(), Date.now(), attachmentDocumentId).idempotencyKey
}

export async function uploadDocumentFile(
  file: File,
  intendedMatterId: string | null,
  idempotencyKey: string,
  onProgress?: (percent: number) => void,
  onControl?: (control: DocumentUploadControl | null) => void,
  attachmentDocumentId?: string,
) {
  let recovery = prepareDocumentUploadRecovery(sessionStorage, file, intendedMatterId, () => idempotencyKey, Date.now(), attachmentDocumentId)
  idempotencyKey = recovery.idempotencyKey

  if (recovery.phase === 'finalizing' && recovery.uploadSessionId) {
    const resumedFinalization = await finalizeDocumentUpload({ uploadSessionId: recovery.uploadSessionId, idempotencyKey })
    if (!('error' in resumedFinalization) || !resumedFinalization.retryable) clearDocumentUploadRecovery(sessionStorage, recovery)
    return resumedFinalization
  }

  const reservation = await reserveDocumentUpload({
    filename: file.name,
    declaredBytes: file.size,
    intendedMatterId,
    idempotencyKey,
    attachmentDocumentId,
  })
  if ('error' in reservation) {
    if (!reservation.retryable) clearDocumentUploadRecovery(sessionStorage, recovery)
    return reservation
  }
  if ('completed' in reservation) {
    clearDocumentUploadRecovery(sessionStorage, recovery)
    return { success: true as const, intakeId: reservation.intakeId }
  }

  recovery = { ...recovery, uploadSessionId: reservation.uploadSessionId, expiresAt: reservation.expiresAt, phase: 'transferring' }
  writeDocumentUploadRecovery(sessionStorage, recovery)

  const transfer = new tus.Upload(file, {
    endpoint: reservation.tusEndpoint,
    headers: { 'x-signature': reservation.signedUploadToken },
    metadata: {
      bucketName: reservation.bucketName,
      objectName: reservation.objectName,
      contentType: 'application/pdf',
      cacheControl: '3600',
    },
    chunkSize: DOCUMENT_UPLOAD_CHUNK_BYTES,
    retryDelays: [0, 3_000, 5_000, 10_000, 20_000],
    uploadDataDuringCreation: true,
    removeFingerprintOnSuccess: true,
    fingerprint: async () => `casechain-document-${reservation.uploadSessionId}`,
    urlStorage: new SessionUploadUrlStorage(),
    onProgress: (sent, total) => onProgress?.(total > 0 ? Math.round((sent / total) * 100) : 0),
  })

  let settled = false
  let settleTransfer: (outcome: TransferOutcome) => void = () => undefined
  const finish = (outcome: TransferOutcome) => {
    if (settled) return
    settled = true
    settleTransfer(outcome)
  }
  const transferResult = new Promise<TransferOutcome>((resolve) => {
    settleTransfer = resolve
    transfer.options.onError = error => finish({ kind: 'error', message: error.message })
    transfer.options.onSuccess = () => finish({ kind: 'transferred' })
  })

  let cancelRequested = false
  let cancellation: Promise<void> | null = null
  onControl?.({
    cancel: async () => {
      if (cancellation) return cancellation
      cancelRequested = true
      cancellation = (async () => {
        const result = await abortThenCancel(
          () => transfer.abort(true),
          () => cancelDocumentUpload({ uploadSessionId: reservation.uploadSessionId, idempotencyKey }),
          error => console.error('TUS upload abort failed:', error),
        )
        finish({ kind: 'cancelled', result })
      })()
      return cancellation
    },
  })

  void startResumableTransfer(
    () => transfer.findPreviousUploads(),
    previous => transfer.resumeFromPreviousUpload(previous),
    () => transfer.start(),
    () => cancelRequested,
  ).catch(error => finish({ kind: 'error', message: error instanceof Error ? error.message : 'Upload could not resume.' }))

  const outcome = await transferResult
  onControl?.(null)
  if (outcome.kind === 'cancelled') {
    if (!('error' in outcome.result) || !outcome.result.retryable) clearDocumentUploadRecovery(sessionStorage, recovery)
    return outcome.result
  }
  if (outcome.kind === 'error') {
    console.error('Private document transfer failed:', outcome.message)
    return {
      error: 'The PDF transfer was interrupted. Retry this file to resume it.',
      retryable: true,
      resolution: 'retry' as const,
      retainIdempotencyKey: true,
    }
  }

  onProgress?.(100)
  recovery = { ...recovery, phase: 'finalizing' }
  writeDocumentUploadRecovery(sessionStorage, recovery)
  const finalization = await finalizeDocumentUpload({ uploadSessionId: reservation.uploadSessionId, idempotencyKey })
  if (!('error' in finalization) || !finalization.retryable) clearDocumentUploadRecovery(sessionStorage, recovery)
  return finalization
}
