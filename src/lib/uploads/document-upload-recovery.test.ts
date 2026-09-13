import assert from 'node:assert/strict'
import test from 'node:test'

import {
  abortThenCancel,
  clearDocumentUploadRecovery,
  prepareDocumentUploadRecovery,
  readDocumentUploadRecovery,
  startResumableTransfer,
  writeDocumentUploadRecovery,
} from './document-upload-recovery'

class MemoryStore {
  values = new Map<string, string>()
  getItem(key: string) { return this.values.get(key) ?? null }
  setItem(key: string, value: string) { this.values.set(key, value) }
  removeItem(key: string) { this.values.delete(key) }
}

const file = { name: 'appeal.pdf', size: 6291456, lastModified: 1700000000000 }
const firstId = '00000000-0000-4000-8000-000000000001'

test('attachment recovery binds the exact document and cannot become ordinary Intake or retarget', () => {
  const store = new MemoryStore()
  const first = prepareDocumentUploadRecovery(store, file, null, () => firstId, 1000, 'document-one')
  assert.equal(readDocumentUploadRecovery(store, file, null, 2000, 'document-one')?.idempotencyKey, first.idempotencyKey)
  assert.equal(readDocumentUploadRecovery(store, file, null, 2000, 'document-two'), null)
  assert.equal(readDocumentUploadRecovery(store, file, null, 2000), null)
})

test('same-tab reload and exact file reselection recover the durable upload identity', () => {
  const store = new MemoryStore()
  const selected = prepareDocumentUploadRecovery(store, file, 'matter-a', () => firstId, 1000)
  const transferring = { ...selected, uploadSessionId: '00000000-0000-4000-8000-000000000002', phase: 'transferring' as const }
  writeDocumentUploadRecovery(store, transferring)

  assert.deepEqual(readDocumentUploadRecovery(store, file, 'matter-a', 2000), transferring)
  assert.equal(prepareDocumentUploadRecovery(store, file, 'matter-a', () => 'unused', 2000).idempotencyKey, firstId)
})

test('rejects stale or mismatched recovery without persisting file bytes, tokens, or paths', () => {
  const store = new MemoryStore()
  const recovery = prepareDocumentUploadRecovery(store, file, null, () => firstId, 1000)
  assert.equal(readDocumentUploadRecovery(store, { ...file, lastModified: file.lastModified + 1 }, null, 2000), null)
  assert.equal(readDocumentUploadRecovery(store, file, 'different-matter', 2000), null)
  assert.equal(readDocumentUploadRecovery(store, file, null, Date.parse(recovery.expiresAt) + 1), null)

  const serialized = [...store.values.values()].join(' ')
  assert.doesNotMatch(serialized, /signed|token|objectName|storage\/v1|%PDF/)
})

test('terminal completion or cancel removes the recovery mapping', () => {
  const store = new MemoryStore()
  const recovery = prepareDocumentUploadRecovery(store, file, null, () => firstId, 1000)
  clearDocumentUploadRecovery(store, recovery)
  assert.equal(readDocumentUploadRecovery(store, file, null, 2000), null)
})

test('TUS abort precedes cancellation and an abort cleanup failure cannot skip the command', async () => {
  const calls: string[] = []
  const result = await abortThenCancel(
    async () => { calls.push('abort'); throw new Error('transport cleanup failed') },
    async () => { calls.push('cancel'); return 'cancelled' },
    () => calls.push('abort-error'),
  )
  assert.equal(result, 'cancelled')
  assert.deepEqual(calls, ['abort', 'abort-error', 'cancel'])
})

test('a cancel request prevents a delayed TUS resume lookup from starting transfer', async () => {
  let releaseLookup: (uploads: readonly string[]) => void = () => undefined
  const lookup = new Promise<readonly string[]>(resolve => { releaseLookup = resolve })
  let cancelled = false
  const calls: string[] = []
  const starting = startResumableTransfer(
    () => lookup,
    upload => calls.push(`resume:${upload}`),
    () => calls.push('start'),
    () => cancelled,
  )

  cancelled = true
  releaseLookup(['stored-upload'])

  assert.equal(await starting, false)
  assert.deepEqual(calls, [])
})
