import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const actionPath = new URL('../actions/document.ts', import.meta.url)
const clientPath = new URL('./resumable-document-upload.ts', import.meta.url)

test('browser transport is signed, resumable, and uses the required chunk size', async () => {
  const source = await readFile(clientPath, 'utf8')

  assert.match(source, /6 \* 1024 \* 1024/)
  assert.match(source, /'x-signature': reservation\.signedUploadToken/)
  assert.match(source, /uploadDataDuringCreation: true/)
  assert.match(source, /removeFingerprintOnSuccess: true/)
  assert.match(source, /findPreviousUploads\(\)/)
  assert.match(source, /onProgress:/)
  assert.match(source, /sessionStorage/)
  assert.match(source, /JSON\.stringify\(\{ \.\.\.upload, metadata: \{\} \}\)/)
  assert.match(source, /prepareDocumentUploadRecovery/)
  assert.match(source, /phase: 'finalizing'/)
  assert.match(source, /abortThenCancel/)
  assert.match(source, /startResumableTransfer/)
  assert.match(source, /cancelDocumentUpload/)
  assert.doesNotMatch(source, /x-upsert/i)
})

test('server actions exchange metadata and opaque identifiers, never browser file bytes', async () => {
  const source = await readFile(actionPath, 'utf8')
  const uploadBoundary = source.slice(
    source.indexOf('type DocumentUploadReservationInput'),
    source.indexOf('function documentUploadError'),
  )

  assert.match(uploadBoundary, /createSignedUploadUrl\(reservation\.object_key, \{ upsert: false \}\)/)
  assert.match(uploadBoundary, /\.eq\('created_by', user\.id\)/)
  assert.match(uploadBoundary, /\.download\(asset\.object_key\)/)
  assert.match(uploadBoundary, /get_document_upload_completion_receipt/)
  assert.match(uploadBoundary, /p_actor: user\.id/)
  assert.match(uploadBoundary, /p_org: orgId/)
  assert.doesNotMatch(uploadBoundary, /FormData|\bas File\b|\.upload\(/)
})
