import assert from 'node:assert/strict'
import test from 'node:test'
import { PDFDocument } from 'pdf-lib'

import {
  transferStagedDocumentBackfillOrganisation,
  type StagedBackfillTransferClient,
} from './staged-backfill-transfer'

async function testPdf() {
  const pdf = await PDFDocument.create()
  pdf.addPage()
  return await pdf.save()
}

test('copies only a freshly granted source, independently re-reads the target, and finalises matching observations', async () => {
  const sourceBytes = await testPdf()
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const accesses: string[] = []
  let destination: Blob | null = null
  const client: StagedBackfillTransferClient = {
    rpc: async (name, args) => {
      calls.push({ name, args })
      if (name === 'claim_staged_document_backfill_transfer_batch') {
        return { data: [{ code: 'transfer_pending', legacy_staged_document_id: 'opaque-id', transfer_lease_token: 'lease-token' }], error: null }
      }
      if (name === 'get_staged_document_backfill_transfer_grant') {
        const crypto = await import('node:crypto')
        return {
          data: [{
            code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf',
            destination_bucket_id: 'documents', destination_object_key: 'preallocated/destination.pdf',
            expected_byte_size: sourceBytes.byteLength,
            expected_sha256: crypto.createHash('sha256').update(sourceBytes).digest('hex'),
          }], error: null,
        }
      }
      return { data: [{ code: 'transferred' }], error: null }
    },
    storage: {
      from: (bucket) => ({
        download: async (path) => {
          accesses.push(`download:${bucket}:${path}`)
          if (bucket === 'staging') {
            const body = sourceBytes.buffer.slice(sourceBytes.byteOffset, sourceBytes.byteOffset + sourceBytes.byteLength) as ArrayBuffer
            return { data: new Blob([body]), error: null }
          }
          return destination
            ? { data: destination, error: null }
            : { data: null, error: { statusCode: 404 } }
        },
        upload: async (path, body, options) => {
          accesses.push(`upload:${bucket}:${path}:${options.upsert}`)
          destination = body
          return { error: null }
        },
      }),
    },
  }

  const metrics = await transferStagedDocumentBackfillOrganisation(client, 'org-id')
  assert.deepEqual(metrics, { claimed: 1, transferred: 1, retryable: 0, skipped: 0, outcomes: { transferred: 1 } })
  assert.deepEqual(accesses, [
    'download:staging:leased/source.pdf',
    'download:documents:preallocated/destination.pdf',
    'upload:documents:preallocated/destination.pdf:false',
    'download:documents:preallocated/destination.pdf',
  ])
  const completion = calls.find((call) => call.name === 'complete_staged_document_backfill_transfer')
  assert.equal(completion?.args.p_source_observed_bytes, sourceBytes.byteLength)
  assert.equal(completion?.args.p_destination_observed_bytes, sourceBytes.byteLength)
  assert.equal(completion?.args.p_source_sha256, completion?.args.p_destination_sha256)
  assert.equal(completion?.args.p_source_page_count, 1)
})

test('does not upload or finalise when the fresh source differs from its verified observation', async () => {
  const sourceBytes = await testPdf()
  const calls: string[] = []
  const client: StagedBackfillTransferClient = {
    rpc: async (name) => {
      calls.push(name)
      if (name === 'claim_staged_document_backfill_transfer_batch') {
        return { data: [{ code: 'transfer_pending', legacy_staged_document_id: 'opaque-id', transfer_lease_token: 'lease-token' }], error: null }
      }
      if (name === 'get_staged_document_backfill_transfer_grant') {
        return {
          data: [{
            code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf',
            destination_bucket_id: 'documents', destination_object_key: 'preallocated/destination.pdf',
            expected_byte_size: sourceBytes.byteLength + 1,
            expected_sha256: 'a'.repeat(64),
          }], error: null,
        }
      }
      throw new Error('unexpected finalisation')
    },
    storage: {
      from: () => ({
        download: async () => {
          const body = sourceBytes.buffer.slice(sourceBytes.byteOffset, sourceBytes.byteOffset + sourceBytes.byteLength) as ArrayBuffer
          return { data: new Blob([body]), error: null }
        },
        upload: async () => {
          throw new Error('unexpected upload')
        },
      }),
    },
  }

  const metrics = await transferStagedDocumentBackfillOrganisation(client, 'org-id')
  assert.deepEqual(metrics, { claimed: 1, transferred: 0, retryable: 0, skipped: 1, outcomes: { source_observation_conflict: 1 } })
  assert.deepEqual(calls, [
    'claim_staged_document_backfill_transfer_batch',
    'get_staged_document_backfill_transfer_grant',
  ])
})

test('records a terminal duplicate reference without classifying it as retryable transfer work', async () => {
  const sourceBytes = await testPdf()
  const crypto = await import('node:crypto')
  const sourceHash = crypto.createHash('sha256').update(sourceBytes).digest('hex')
  const client: StagedBackfillTransferClient = {
    rpc: async (name) => {
      if (name === 'claim_staged_document_backfill_transfer_batch') {
        return { data: [{ code: 'transfer_pending', legacy_staged_document_id: 'opaque-id', transfer_lease_token: 'lease-token' }], error: null }
      }
      if (name === 'get_staged_document_backfill_transfer_grant') {
        return {
          data: [{
            code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf',
            destination_bucket_id: 'documents', destination_object_key: 'preallocated/destination.pdf',
            expected_byte_size: sourceBytes.byteLength, expected_sha256: sourceHash,
          }], error: null,
        }
      }
      return { data: [{ code: 'duplicate_reference' }], error: null }
    },
    storage: {
      from: () => ({
        download: async () => {
          const body = sourceBytes.buffer.slice(sourceBytes.byteOffset, sourceBytes.byteOffset + sourceBytes.byteLength) as ArrayBuffer
          return { data: new Blob([body]), error: null }
        },
        upload: async () => {
          throw new Error('destination was already independently reachable')
        },
      }),
    },
  }

  const metrics = await transferStagedDocumentBackfillOrganisation(client, 'org-id')
  assert.deepEqual(metrics, { claimed: 1, transferred: 0, retryable: 0, skipped: 1, outcomes: { duplicate_reference: 1 } })
})
