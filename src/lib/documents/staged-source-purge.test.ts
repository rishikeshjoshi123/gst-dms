import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import test from 'node:test'
import { PDFDocument } from 'pdf-lib'

import {
  purgeStagedDocumentSourcesForOrganisation,
  type StagedSourcePurgeClient,
} from './staged-source-purge'

async function testPdf() {
  const pdf = await PDFDocument.create()
  pdf.addPage()
  return await pdf.save()
}

function blob(bytes: Uint8Array) {
  const body = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer
  return new Blob([body])
}

test('records intent before deleting only a freshly granted equal readable source and confirms a content-free tombstone', async () => {
  const bytes = await testPdf()
  const sha256 = createHash('sha256').update(bytes).digest('hex')
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const accesses: string[] = []
  const client: StagedSourcePurgeClient = {
    rpc: async (name, args) => {
      calls.push({ name, args })
      if (name === 'claim_staged_document_source_purge_batch') {
        return { data: [{ code: 'purge_required', legacy_staged_document_id: 'opaque-id', purge_lease_token: 'lease-token' }], error: null }
      }
      if (name === 'get_staged_document_source_purge_grant') {
        return { data: [{
          code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf',
          destination_bucket_id: 'documents', destination_object_key: 'leased/canonical.pdf',
          expected_byte_size: bytes.byteLength, expected_sha256: sha256,
        }], error: null }
      }
      if (name === 'record_staged_document_source_purge_intent') return { data: [{ code: 'delete_intended' }], error: null }
      if (name === 'confirm_staged_document_source_purge') return { data: [{ code: 'deleted' }], error: null }
      throw new Error(`unexpected RPC ${name}`)
    },
    storage: {
      from: (bucket) => ({
        download: async (path) => {
          accesses.push(`download:${bucket}:${path}`)
          return { data: blob(bytes), error: null }
        },
        remove: async (paths) => {
          accesses.push(`remove:${bucket}:${paths.join(',')}`)
          return { error: null }
        },
      }),
    },
  }

  const metrics = await purgeStagedDocumentSourcesForOrganisation(client, 'org-id')
  assert.deepEqual(metrics, { claimed: 1, deleted: 1, recovery: 0, retryable: 0, skipped: 0, outcomes: { deleted: 1 } })
  assert.deepEqual(accesses, [
    'download:staging:leased/source.pdf',
    'download:documents:leased/canonical.pdf',
    'remove:staging:leased/source.pdf',
  ])
  assert.deepEqual(calls.map((call) => call.name), [
    'claim_staged_document_source_purge_batch',
    'get_staged_document_source_purge_grant',
    'record_staged_document_source_purge_intent',
    'get_staged_document_source_purge_grant',
    'confirm_staged_document_source_purge',
  ])
  const intent = calls.find((call) => call.name === 'record_staged_document_source_purge_intent')
  assert.equal(intent?.args.p_source_sha256, sha256)
  assert.equal(intent?.args.p_destination_sha256, sha256)
  assert.equal(intent?.args.p_source_page_count, 1)
  assert.equal(intent?.args.p_destination_page_count, 1)
  assert.equal(calls.at(-1)?.args.p_confirmation, 'storage_deleted')
})

test('enters durable recovery instead of deleting when the fresh canonical bytes differ', async () => {
  const source = await testPdf()
  const destinationPdf = await PDFDocument.create()
  destinationPdf.addPage()
  destinationPdf.addPage()
  const destination = await destinationPdf.save()
  const sha256 = createHash('sha256').update(source).digest('hex')
  const calls: string[] = []
  const client: StagedSourcePurgeClient = {
    rpc: async (name) => {
      calls.push(name)
      if (name === 'claim_staged_document_source_purge_batch') return { data: [{ code: 'purge_required', legacy_staged_document_id: 'opaque-id', purge_lease_token: 'lease-token' }], error: null }
      if (name === 'get_staged_document_source_purge_grant') return { data: [{
        code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf',
        destination_bucket_id: 'documents', destination_object_key: 'leased/canonical.pdf',
        expected_byte_size: source.byteLength, expected_sha256: sha256,
      }], error: null }
      if (name === 'record_staged_document_source_purge_recovery') return { data: [{ code: 'recovery_required' }], error: null }
      throw new Error(`unexpected RPC ${name}`)
    },
    storage: {
      from: (bucket) => ({
        download: async () => ({ data: blob(bucket === 'staging' ? source : destination), error: null }),
        remove: async () => {
          throw new Error('source must not be deleted after a contradiction')
        },
      }),
    },
  }

  const metrics = await purgeStagedDocumentSourcesForOrganisation(client, 'org-id')
  assert.deepEqual(metrics, { claimed: 1, deleted: 0, recovery: 1, retryable: 0, skipped: 0, outcomes: { recovery_required: 1 } })
  assert.deepEqual(calls, [
    'claim_staged_document_source_purge_batch',
    'get_staged_document_source_purge_grant',
    'record_staged_document_source_purge_recovery',
  ])
})

test('never writes terminal state or deletes after a transient source download error', async () => {
  const client: StagedSourcePurgeClient = {
    rpc: async (name) => {
      if (name === 'claim_staged_document_source_purge_batch') return { data: [{ code: 'purge_required', legacy_staged_document_id: 'opaque-id', purge_lease_token: 'lease-token' }], error: null }
      if (name === 'get_staged_document_source_purge_grant') return { data: [{
        code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf',
        destination_bucket_id: 'documents', destination_object_key: 'leased/canonical.pdf',
        expected_byte_size: 1, expected_sha256: 'a'.repeat(64),
      }], error: null }
      throw new Error('terminal RPC must not run')
    },
    storage: {
      from: () => ({
        download: async () => ({ data: null, error: { statusCode: 503 } }),
        remove: async () => {
          throw new Error('remove must not run')
        },
      }),
    },
  }

  const metrics = await purgeStagedDocumentSourcesForOrganisation(client, 'org-id')
  assert.deepEqual(metrics, { claimed: 1, deleted: 0, recovery: 0, retryable: 1, skipped: 0, outcomes: { source_retryable: 1 } })
})

test('turns a database contradiction into durable recovery without receiving a storage key', async () => {
  const calls: string[] = []
  const client: StagedSourcePurgeClient = {
    rpc: async (name) => {
      calls.push(name)
      if (name === 'claim_staged_document_source_purge_batch') return { data: [{ code: 'purge_required', legacy_staged_document_id: 'opaque-id', purge_lease_token: 'lease-token' }], error: null }
      if (name === 'get_staged_document_source_purge_grant') return { data: [{ code: 'database_inconsistent' }], error: null }
      if (name === 'record_staged_document_source_purge_recovery') return { data: [{ code: 'recovery_required' }], error: null }
      throw new Error(`unexpected RPC ${name}`)
    },
    storage: {
      from: () => ({
        download: async () => {
          throw new Error('no storage access is allowed without a grant')
        },
        remove: async () => {
          throw new Error('no storage access is allowed without a grant')
        },
      }),
    },
  }

  const metrics = await purgeStagedDocumentSourcesForOrganisation(client, 'org-id')
  assert.deepEqual(metrics, { claimed: 1, deleted: 0, recovery: 1, retryable: 0, skipped: 0, outcomes: { recovery_required: 1 } })
  assert.deepEqual(calls, [
    'claim_staged_document_source_purge_batch',
    'get_staged_document_source_purge_grant',
    'record_staged_document_source_purge_recovery',
  ])
})

test('fences durable recovery when canonical eligibility changes after intent and before Storage delete', async () => {
  const bytes = await testPdf()
  const sha256 = createHash('sha256').update(bytes).digest('hex')
  const calls: string[] = []
  let grantCount = 0
  const client: StagedSourcePurgeClient = {
    rpc: async (name) => {
      calls.push(name)
      if (name === 'claim_staged_document_source_purge_batch') return { data: [{ code: 'purge_required', legacy_staged_document_id: 'opaque-id', purge_lease_token: 'lease-token' }], error: null }
      if (name === 'get_staged_document_source_purge_grant') {
        grantCount += 1
        return grantCount === 1
          ? { data: [{ code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf', destination_bucket_id: 'documents', destination_object_key: 'leased/canonical.pdf', expected_byte_size: bytes.byteLength, expected_sha256: sha256 }], error: null }
          : { data: [{ code: 'not_eligible' }], error: null }
      }
      if (name === 'record_staged_document_source_purge_intent') return { data: [{ code: 'delete_intended' }], error: null }
      if (name === 'record_staged_document_source_purge_recovery') return { data: [{ code: 'recovery_required' }], error: null }
      throw new Error(`unexpected RPC ${name}`)
    },
    storage: {
      from: (bucket) => ({
        download: async () => ({ data: blob(bytes), error: null }),
        remove: async () => {
          throw new Error(`Storage delete must not run after eligibility changes in ${bucket}`)
        },
      }),
    },
  }

  const metrics = await purgeStagedDocumentSourcesForOrganisation(client, 'org-id')
  assert.deepEqual(metrics, { claimed: 1, deleted: 0, recovery: 1, retryable: 0, skipped: 0, outcomes: { recovery_required: 1 } })
  assert.deepEqual(calls, [
    'claim_staged_document_source_purge_batch',
    'get_staged_document_source_purge_grant',
    'record_staged_document_source_purge_intent',
    'get_staged_document_source_purge_grant',
    'record_staged_document_source_purge_recovery',
  ])
})

test('reconciles a trusted source 404 only through an earlier durable intent, otherwise fences recovery', async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const client: StagedSourcePurgeClient = {
    rpc: async (name, args) => {
      calls.push({ name, args })
      if (name === 'claim_staged_document_source_purge_batch') return { data: [{ code: 'purge_required', legacy_staged_document_id: 'opaque-id', purge_lease_token: 'lease-token' }], error: null }
      if (name === 'get_staged_document_source_purge_grant') return { data: [{
        code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf',
        destination_bucket_id: 'documents', destination_object_key: 'leased/canonical.pdf',
        expected_byte_size: 1, expected_sha256: 'a'.repeat(64),
      }], error: null }
      if (name === 'confirm_staged_document_source_purge') return { data: [{ code: 'intent_not_recorded' }], error: null }
      if (name === 'record_staged_document_source_purge_recovery') return { data: [{ code: 'recovery_required' }], error: null }
      throw new Error(`unexpected RPC ${name}`)
    },
    storage: {
      from: () => ({
        download: async () => ({ data: null, error: { status: 404 } }),
        remove: async () => {
          throw new Error('remove must not run')
        },
      }),
    },
  }

  const metrics = await purgeStagedDocumentSourcesForOrganisation(client, 'org-id')
  assert.deepEqual(metrics, { claimed: 1, deleted: 0, recovery: 1, retryable: 0, skipped: 0, outcomes: { recovery_required: 1 } })
  assert.equal(calls.find((call) => call.name === 'confirm_staged_document_source_purge')?.args.p_confirmation, 'storage_missing_after_intent')
  assert.equal(calls.find((call) => call.name === 'record_staged_document_source_purge_recovery')?.args.p_recovery_code, 'source_missing_before_intent')
})
