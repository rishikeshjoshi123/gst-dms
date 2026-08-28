import assert from 'node:assert/strict'
import test from 'node:test'
import { PDFDocument } from 'pdf-lib'

import {
  observeStagedDocumentBytes,
  verifyStagedDocumentBackfillOrganisation,
  type StagedBackfillClient,
} from './staged-backfill-verifier'

test('derives a hash and byte count only for a readable PDF', async () => {
  const pdf = await PDFDocument.create()
  pdf.addPage()
  const bytes = await pdf.save()

  const observed = await observeStagedDocumentBytes(bytes)
  assert.equal(observed.sourceResult, 'valid_pdf')
  assert.equal(observed.observedBytes, bytes.byteLength)
  assert.match(observed.sha256 ?? '', /^[0-9a-f]{64}$/)
})

test('classifies a non-PDF before invoking the PDF reader', async () => {
  let invoked = false
  const observed = await observeStagedDocumentBytes(new Uint8Array([1, 2, 3]), async () => {
    invoked = true
    return { outcome: 'ready', pageCount: 1 }
  })
  assert.equal(observed.sourceResult, 'non_pdf')
  assert.equal(invoked, false)
  assert.equal(observed.sha256, undefined)
})

test('maps encrypted and oversized PDF observations to the backfill contract enums', async () => {
  const pdfLike = new TextEncoder().encode('%PDF-1.7\n')
  const encrypted = await observeStagedDocumentBytes(pdfLike, async () => ({ outcome: 'encrypted_pdf', pageCount: null }))
  assert.equal(encrypted.sourceResult, 'encrypted_pdf')

  let invoked = false
  const oversized = await observeStagedDocumentBytes(pdfLike, async () => {
    invoked = true
    return { outcome: 'ready', pageCount: 1 }
  }, 4)
  assert.equal(oversized.sourceResult, 'oversize')
  assert.equal(invoked, false)
})

test('uses only a leased source grant and records a safe observation', async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const paths: string[] = []
  const pdf = await PDFDocument.create()
  pdf.addPage()
  const bytes = await pdf.save()
  const client: StagedBackfillClient = {
    rpc: async (name, args) => {
      calls.push({ name, args })
      if (name === 'claim_staged_document_backfill_batch') {
        return { data: [{ code: 'verification_required', legacy_staged_document_id: 'opaque-id', verification_lease_token: 'lease-token' }], error: null }
      }
      if (name === 'get_staged_document_backfill_source_grant') {
        return { data: [{ code: 'ok', bucket_id: 'staging', object_key: 'trusted/by/sql/original.pdf' }], error: null }
      }
      return { data: [{ code: 'transfer_pending' }], error: null }
    },
    storage: {
      from: (bucket) => ({
        download: async (path) => {
          paths.push(`${bucket}:${path}`)
          const body = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer
          return { data: new Blob([body]), error: null }
        },
      }),
    },
  }

  const metrics = await verifyStagedDocumentBackfillOrganisation(client, 'org-id')
  assert.deepEqual(metrics, { claimed: 1, classified: 1, retryable: 0, skipped: 0, outcomes: { transfer_pending: 1 } })
  assert.deepEqual(paths, ['staging:trusted/by/sql/original.pdf'])
  const record = calls.find((call) => call.name === 'record_staged_document_backfill_verification')
  assert.equal(record?.args.p_source_result, 'valid_pdf')
  assert.match(String(record?.args.p_sha256), /^[0-9a-f]{64}$/)
})

test('records missing only for an explicit trusted-storage 404 and leaves transient errors retryable', async () => {
  const run = async (error: unknown) => {
    const recorded: Record<string, unknown>[] = []
    const client: StagedBackfillClient = {
      rpc: async (name, args) => {
        if (name === 'claim_staged_document_backfill_batch') return { data: [{ code: 'verification_required', legacy_staged_document_id: 'opaque-id', verification_lease_token: 'lease-token' }], error: null }
        if (name === 'get_staged_document_backfill_source_grant') return { data: [{ code: 'ok', bucket_id: 'staging', object_key: 'trusted' }], error: null }
        recorded.push(args)
        return { data: [{ code: 'missing_object' }], error: null }
      },
      storage: { from: () => ({ download: async () => ({ data: null, error }) }) },
    }
    return { metrics: await verifyStagedDocumentBackfillOrganisation(client, 'org-id'), recorded }
  }

  const missing = await run({ statusCode: 404 })
  assert.equal(missing.recorded[0]?.p_source_result, 'missing')
  assert.equal(missing.metrics.classified, 1)

  const transient = await run({ statusCode: 503 })
  assert.equal(transient.recorded.length, 0)
  assert.equal(transient.metrics.retryable, 1)
})
