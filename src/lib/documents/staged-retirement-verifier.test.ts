import assert from 'node:assert/strict'
import test from 'node:test'
import { createHash } from 'node:crypto'

import {
  auditStagedDocumentRetirementOrganisation,
  type StagedRetirementAuditClient,
} from './staged-retirement-verifier'

const bytes = new TextEncoder().encode('%PDF-1.7\nretirement-proof')
const sha256 = createHash('sha256').update(bytes).digest('hex')

function blob() {
  const body = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer
  return new Blob([body])
}

test('uses only a fresh audit grant and records equal source/destination proof', async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const accesses: string[] = []
  const client: StagedRetirementAuditClient = {
    rpc: async (name, args) => {
      calls.push({ name, args })
      if (name === 'claim_staged_document_retirement_audit_batch') {
        return { data: [{ code: 'audit_required', legacy_staged_document_id: 'opaque-id', audit_lease_token: 'lease-token' }], error: null }
      }
      if (name === 'get_staged_document_retirement_audit_grant') {
        return { data: [{
          code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf',
          destination_bucket_id: 'documents', destination_object_key: 'leased/destination.pdf',
          expected_byte_size: bytes.byteLength, expected_sha256: sha256,
        }], error: null }
      }
      return { data: [{ code: 'verified_equal' }], error: null }
    },
    storage: {
      from: (bucket) => ({
        download: async (path) => {
          accesses.push(`${bucket}:${path}`)
          return { data: blob(), error: null }
        },
      }),
    },
  }

  const metrics = await auditStagedDocumentRetirementOrganisation(client, 'org-id')
  assert.deepEqual(metrics, { claimed: 1, verified: 1, retryable: 0, skipped: 0, outcomes: { verified_equal: 1 } })
  assert.deepEqual(accesses, ['staging:leased/source.pdf', 'documents:leased/destination.pdf'])
  const record = calls.find((call) => call.name === 'record_staged_document_retirement_audit')
  assert.equal(record?.args.p_outcome, 'verified_equal')
  assert.equal(record?.args.p_source_observed_bytes, bytes.byteLength)
  assert.equal(record?.args.p_destination_observed_bytes, bytes.byteLength)
  assert.equal(record?.args.p_source_sha256, sha256)
  assert.equal(record?.args.p_destination_sha256, sha256)
})

test('records an explicit destination-missing result only for a trusted 404', async () => {
  const recorded: Record<string, unknown>[] = []
  const client: StagedRetirementAuditClient = {
    rpc: async (name, args) => {
      if (name === 'claim_staged_document_retirement_audit_batch') return { data: [{ code: 'audit_required', legacy_staged_document_id: 'opaque-id', audit_lease_token: 'lease-token' }], error: null }
      if (name === 'get_staged_document_retirement_audit_grant') return { data: [{
        code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf',
        destination_bucket_id: 'documents', destination_object_key: 'leased/destination.pdf',
        expected_byte_size: bytes.byteLength, expected_sha256: sha256,
      }], error: null }
      recorded.push(args)
      return { data: [{ code: 'destination_missing' }], error: null }
    },
    storage: {
      from: (bucket) => ({
        download: async () => bucket === 'staging'
          ? { data: blob(), error: null }
          : { data: null, error: { statusCode: 404 } },
      }),
    },
  }

  const metrics = await auditStagedDocumentRetirementOrganisation(client, 'org-id')
  assert.equal(recorded[0]?.p_outcome, 'destination_missing')
  assert.equal(recorded[0]?.p_source_sha256, null)
  assert.equal(metrics.skipped, 1)
  assert.deepEqual(metrics.outcomes, { destination_missing: 1 })
})

test('records source-missing evidence only for a trusted source 404', async () => {
  const recorded: Record<string, unknown>[] = []
  const client: StagedRetirementAuditClient = {
    rpc: async (name, args) => {
      if (name === 'claim_staged_document_retirement_audit_batch') return { data: [{ code: 'audit_required', legacy_staged_document_id: 'opaque-id', audit_lease_token: 'lease-token' }], error: null }
      if (name === 'get_staged_document_retirement_audit_grant') return { data: [{
        code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf',
        destination_bucket_id: 'documents', destination_object_key: 'leased/destination.pdf',
        expected_byte_size: bytes.byteLength, expected_sha256: sha256,
      }], error: null }
      recorded.push(args)
      return { data: [{ code: 'source_missing' }], error: null }
    },
    storage: { from: () => ({ download: async () => ({ data: null, error: { status: 404 } }) }) },
  }

  const metrics = await auditStagedDocumentRetirementOrganisation(client, 'org-id')
  assert.equal(recorded[0]?.p_outcome, 'source_missing')
  assert.equal(recorded[0]?.p_source_observed_bytes, null)
  assert.deepEqual(metrics, { claimed: 1, verified: 0, retryable: 0, skipped: 1, outcomes: { source_missing: 1 } })
})

test('records source and destination conflicts without passing observations into the report contract', async () => {
  const run = async (destinationBytes?: Uint8Array, expectedHash = sha256) => {
    const recorded: Record<string, unknown>[] = []
    const client: StagedRetirementAuditClient = {
      rpc: async (name, args) => {
        if (name === 'claim_staged_document_retirement_audit_batch') return { data: [{ code: 'audit_required', legacy_staged_document_id: 'opaque-id', audit_lease_token: 'lease-token' }], error: null }
        if (name === 'get_staged_document_retirement_audit_grant') return { data: [{
          code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf',
          destination_bucket_id: 'documents', destination_object_key: 'leased/destination.pdf',
          expected_byte_size: bytes.byteLength, expected_sha256: expectedHash,
        }], error: null }
        recorded.push(args)
        return { data: [{ code: args.p_outcome }], error: null }
      },
      storage: {
        from: (bucket) => ({
          download: async () => {
            const candidate = bucket === 'documents' && destinationBytes ? destinationBytes : bytes
            const body = candidate.buffer.slice(candidate.byteOffset, candidate.byteOffset + candidate.byteLength) as ArrayBuffer
            return { data: new Blob([body]), error: null }
          },
        }),
      },
    }
    return { metrics: await auditStagedDocumentRetirementOrganisation(client, 'org-id'), recorded }
  }

  const destinationConflict = await run(new TextEncoder().encode('%PDF-1.7\ndifferent'))
  assert.equal(destinationConflict.recorded[0]?.p_outcome, 'destination_observation_conflict')
  assert.equal(destinationConflict.recorded[0]?.p_destination_sha256, null)
  assert.equal(destinationConflict.metrics.skipped, 1)

  const sourceConflict = await run(undefined, '0'.repeat(64))
  assert.equal(sourceConflict.recorded[0]?.p_outcome, 'source_observation_conflict')
  assert.equal(sourceConflict.recorded[0]?.p_source_sha256, null)
  assert.equal(sourceConflict.metrics.skipped, 1)
})

test('does not record a terminal proof result for transient storage failures', async () => {
  const client: StagedRetirementAuditClient = {
    rpc: async (name) => {
      if (name === 'claim_staged_document_retirement_audit_batch') return { data: [{ code: 'audit_required', legacy_staged_document_id: 'opaque-id', audit_lease_token: 'lease-token' }], error: null }
      if (name === 'get_staged_document_retirement_audit_grant') return { data: [{
        code: 'ok', source_bucket_id: 'staging', source_object_key: 'leased/source.pdf',
        destination_bucket_id: 'documents', destination_object_key: 'leased/destination.pdf',
        expected_byte_size: bytes.byteLength, expected_sha256: sha256,
      }], error: null }
      throw new Error('record should not be called')
    },
    storage: { from: () => ({ download: async () => ({ data: null, error: { statusCode: 503 } }) }) },
  }

  const metrics = await auditStagedDocumentRetirementOrganisation(client, 'org-id')
  assert.deepEqual(metrics, { claimed: 1, verified: 0, retryable: 1, skipped: 0, outcomes: { source_retryable: 1 } })
})
