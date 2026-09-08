'use client'

import * as tus from 'tus-js-client'

import { finalizeDocumentUpload, reserveDocumentUpload } from '@/lib/actions/document'

export const DOCUMENT_UPLOAD_CHUNK_BYTES = 6 * 1024 * 1024

type StoredUpload = {
  size: number | null
  metadata: Record<string, string>
  creationTime: string
  urlStorageKey: string
  uploadUrl: string | null
  parallelUploadUrls: string[] | null
}

class SessionUploadUrlStorage {
  private prefix = 'casechain-tus::'

  async findAllUploads() {
    return this.findEntries(this.prefix)
  }

  async findUploadsByFingerprint(fingerprint: string) {
    return this.findEntries(`${this.prefix}${fingerprint}::`)
  }

  async removeUpload(urlStorageKey: string) {
    sessionStorage.removeItem(urlStorageKey)
  }

  async addUpload(fingerprint: string, upload: StoredUpload) {
    const key = `${this.prefix}${fingerprint}::${crypto.randomUUID()}`
    sessionStorage.setItem(key, JSON.stringify(upload))
    return key
  }

  private findEntries(prefix: string) {
    const uploads: StoredUpload[] = []
    for (let index = 0; index < sessionStorage.length; index++) {
      const key = sessionStorage.key(index)
      if (!key?.startsWith(prefix)) continue
      try {
        const upload = JSON.parse(sessionStorage.getItem(key) ?? '') as StoredUpload
        uploads.push({ ...upload, urlStorageKey: key })
      } catch {
        sessionStorage.removeItem(key)
      }
    }
    return uploads
  }
}

export async function uploadDocumentFile(
  file: File,
  intendedMatterId: string | null,
  idempotencyKey: string,
  onProgress?: (percent: number) => void,
) {
  const reservation = await reserveDocumentUpload({
    filename: file.name,
    declaredBytes: file.size,
    intendedMatterId,
    idempotencyKey,
  })
  if ('error' in reservation) return reservation

  const finalizationMarker = `casechain-upload-ready::${reservation.uploadSessionId}`
  if (sessionStorage.getItem(finalizationMarker) === 'true') {
    const resumedFinalization = await finalizeDocumentUpload({
      uploadSessionId: reservation.uploadSessionId,
      idempotencyKey,
    })
    if (!('error' in resumedFinalization) || !resumedFinalization.retryable) sessionStorage.removeItem(finalizationMarker)
    return resumedFinalization
  }

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

  const transferResult = await new Promise<{ error?: string }>((resolve) => {
    transfer.options.onError = error => resolve({ error: error.message })
    transfer.options.onSuccess = () => resolve({})
    void transfer.findPreviousUploads().then(previous => {
      if (previous[0]) transfer.resumeFromPreviousUpload(previous[0])
      transfer.start()
    }).catch(error => resolve({ error: error instanceof Error ? error.message : 'Upload could not resume.' }))
  })

  if (transferResult.error) {
    console.error('Private document transfer failed:', transferResult.error)
    return {
      error: 'The PDF transfer was interrupted. Retry this file to resume it.',
      retryable: true,
      resolution: 'retry' as const,
      retainIdempotencyKey: true,
    }
  }

  onProgress?.(100)
  sessionStorage.setItem(finalizationMarker, 'true')
  const finalization = await finalizeDocumentUpload({ uploadSessionId: reservation.uploadSessionId, idempotencyKey })
  if (!('error' in finalization) || !finalization.retryable) sessionStorage.removeItem(finalizationMarker)
  return finalization
}
