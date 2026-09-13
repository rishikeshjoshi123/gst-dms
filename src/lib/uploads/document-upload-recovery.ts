export const DOCUMENT_UPLOAD_RECOVERY_TTL_MS = 24 * 60 * 60 * 1000

export type DocumentUploadFingerprint = {
  name: string
  size: number
  lastModified: number
  intendedMatterId: string | null
  attachmentDocumentId?: string
}

export type DocumentUploadRecovery = {
  version: 1
  fingerprint: DocumentUploadFingerprint
  idempotencyKey: string
  uploadSessionId?: string
  expiresAt: string
  phase: 'selected' | 'transferring' | 'finalizing'
}

type SessionStore = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>
type FileIdentity = Pick<File, 'name' | 'size' | 'lastModified'>

const RECOVERY_PREFIX = 'casechain-document-upload::v1::'
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function documentUploadFingerprint(file: FileIdentity, intendedMatterId: string | null, attachmentDocumentId?: string): DocumentUploadFingerprint {
  return {
    name: file.name.slice(0, 255),
    size: file.size,
    lastModified: file.lastModified,
    intendedMatterId,
    ...(attachmentDocumentId ? { attachmentDocumentId } : {}),
  }
}

function fingerprintKey(fingerprint: DocumentUploadFingerprint) {
  const value = JSON.stringify(fingerprint)
  let hash = 2166136261
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  return `${RECOVERY_PREFIX}${(hash >>> 0).toString(16).padStart(8, '0')}`
}

function sameFingerprint(left: DocumentUploadFingerprint, right: DocumentUploadFingerprint) {
  return left.name === right.name
    && left.size === right.size
    && left.lastModified === right.lastModified
    && left.intendedMatterId === right.intendedMatterId
    && left.attachmentDocumentId === right.attachmentDocumentId
}

function validRecovery(value: unknown, fingerprint: DocumentUploadFingerprint, now: number): value is DocumentUploadRecovery {
  if (!value || typeof value !== 'object') return false
  const candidate = value as Partial<DocumentUploadRecovery>
  return candidate.version === 1
    && candidate.fingerprint !== undefined
    && sameFingerprint(candidate.fingerprint, fingerprint)
    && typeof candidate.idempotencyKey === 'string'
    && UUID_PATTERN.test(candidate.idempotencyKey)
    && (candidate.uploadSessionId === undefined || UUID_PATTERN.test(candidate.uploadSessionId))
    && typeof candidate.expiresAt === 'string'
    && Number.isFinite(Date.parse(candidate.expiresAt))
    && Date.parse(candidate.expiresAt) > now
    && (candidate.phase === 'selected' || candidate.phase === 'transferring' || candidate.phase === 'finalizing')
}

export function readDocumentUploadRecovery(
  store: SessionStore,
  file: FileIdentity,
  intendedMatterId: string | null,
  now = Date.now(),
  attachmentDocumentId?: string,
) {
  const fingerprint = documentUploadFingerprint(file, intendedMatterId, attachmentDocumentId)
  const key = fingerprintKey(fingerprint)
  const stored = store.getItem(key)
  if (!stored) return null
  try {
    const parsed: unknown = JSON.parse(stored)
    if (validRecovery(parsed, fingerprint, now)) return parsed
  } catch {}
  store.removeItem(key)
  return null
}

export function prepareDocumentUploadRecovery(
  store: SessionStore,
  file: FileIdentity,
  intendedMatterId: string | null,
  createId: () => string,
  now = Date.now(),
  attachmentDocumentId?: string,
) {
  const recovered = readDocumentUploadRecovery(store, file, intendedMatterId, now, attachmentDocumentId)
  if (recovered) return recovered
  const recovery: DocumentUploadRecovery = {
    version: 1,
    fingerprint: documentUploadFingerprint(file, intendedMatterId, attachmentDocumentId),
    idempotencyKey: createId(),
    expiresAt: new Date(now + DOCUMENT_UPLOAD_RECOVERY_TTL_MS).toISOString(),
    phase: 'selected',
  }
  store.setItem(fingerprintKey(recovery.fingerprint), JSON.stringify(recovery))
  return recovery
}

export function writeDocumentUploadRecovery(store: SessionStore, recovery: DocumentUploadRecovery) {
  store.setItem(fingerprintKey(recovery.fingerprint), JSON.stringify(recovery))
}

export function clearDocumentUploadRecovery(store: SessionStore, recovery: DocumentUploadRecovery) {
  store.removeItem(fingerprintKey(recovery.fingerprint))
}

/** Stop browser transfer first, but never let a TUS cleanup failure skip authority cancellation. */
export async function abortThenCancel<T>(
  abort: () => Promise<void>,
  cancel: () => Promise<T>,
  onAbortError: (error: unknown) => void = () => undefined,
) {
  try {
    await abort()
  } catch (error) {
    onAbortError(error)
  }
  return cancel()
}

/** Do not let an asynchronous resume lookup restart a transfer after cancel. */
export async function startResumableTransfer<T>(
  findPrevious: () => Promise<readonly T[]>,
  resume: (upload: T) => void,
  start: () => void,
  isCancelled: () => boolean,
) {
  const previous = await findPrevious()
  if (isCancelled()) return false
  if (previous[0]) resume(previous[0])
  start()
  return true
}
