import { createHash } from 'node:crypto'

import { STAGED_BACKFILL_MAX_OBJECT_BYTES, type StagedBackfillClient } from './staged-backfill-verifier'

export const STAGED_RETIREMENT_AUDIT_BATCH_SIZE = 10

type RpcRow = Record<string, unknown>

export type StagedRetirementAuditOutcome =
  | 'verified_equal'
  | 'source_missing'
  | 'destination_missing'
  | 'source_observation_conflict'
  | 'destination_observation_conflict'

export type StagedRetirementAuditMetrics = {
  claimed: number
  verified: number
  retryable: number
  skipped: number
  outcomes: Record<string, number>
}

type RetirementStorageClient = {
  from(bucket: string): {
    download(path: string): Promise<{ data: Blob | null; error: unknown }>
  }
}

export type StagedRetirementAuditClient = Omit<StagedBackfillClient, 'storage'> & {
  storage: RetirementStorageClient
}

function emptyMetrics(): StagedRetirementAuditMetrics {
  return { claimed: 0, verified: 0, retryable: 0, skipped: 0, outcomes: {} }
}

function count(metrics: StagedRetirementAuditMetrics, code: string) {
  metrics.outcomes[code] = (metrics.outcomes[code] ?? 0) + 1
}

async function rpcRows(client: StagedRetirementAuditClient, name: string, args: Record<string, unknown>): Promise<RpcRow[]> {
  const result = await client.rpc(name, args)
  if (result.error) throw new Error('Staged document retirement audit service operation unavailable')
  return Array.isArray(result.data) ? result.data.filter((row): row is RpcRow => !!row && typeof row === 'object') : []
}

async function rpcRow(client: StagedRetirementAuditClient, name: string, args: Record<string, unknown>) {
  return (await rpcRows(client, name, args))[0] ?? null
}

function isMissingStorageError(error: unknown) {
  if (!error || typeof error !== 'object') return false
  const candidate = error as { status?: unknown; statusCode?: unknown; code?: unknown }
  return String(candidate.status) === '404' || String(candidate.statusCode) === '404' || candidate.code === '404'
}

function hasOpaqueClaim(row: RpcRow): row is RpcRow & {
  code: 'audit_required'
  legacy_staged_document_id: string
  audit_lease_token: string
} {
  return row.code === 'audit_required'
    && typeof row.legacy_staged_document_id === 'string'
    && typeof row.audit_lease_token === 'string'
}

function hasAuditGrant(row: RpcRow): row is RpcRow & {
  code: 'ok'
  source_bucket_id: string
  source_object_key: string
  destination_bucket_id: string
  destination_object_key: string
  expected_byte_size: number
  expected_sha256: string
} {
  return row.code === 'ok'
    && typeof row.source_bucket_id === 'string'
    && typeof row.source_object_key === 'string'
    && typeof row.destination_bucket_id === 'string'
    && typeof row.destination_object_key === 'string'
    && typeof row.expected_byte_size === 'number'
    && Number.isSafeInteger(row.expected_byte_size)
    && typeof row.expected_sha256 === 'string'
    && /^[0-9a-f]{64}$/.test(row.expected_sha256)
}

type DownloadObservation = { found: true; byteSize: number; sha256: string } | { found: false } | null

async function observeDownload(
  client: StagedRetirementAuditClient,
  bucket: string,
  objectKey: string,
): Promise<DownloadObservation> {
  const downloaded = await client.storage.from(bucket).download(objectKey)
  if (downloaded.error) return isMissingStorageError(downloaded.error) ? { found: false } : null
  if (!downloaded.data) return null
  const bytes = new Uint8Array(await downloaded.data.arrayBuffer())
  if (bytes.byteLength > STAGED_BACKFILL_MAX_OBJECT_BYTES) return null
  return { found: true, byteSize: bytes.byteLength, sha256: createHash('sha256').update(bytes).digest('hex') }
}

/**
 * Re-reads each completed transfer using only a fresh service grant. Metrics
 * are aggregate-only; the caller never receives paths, ids, hashes, bytes,
 * content, or Storage error details.
 */
export async function auditStagedDocumentRetirementOrganisation(
  client: StagedRetirementAuditClient,
  orgId: string,
  batchSize = STAGED_RETIREMENT_AUDIT_BATCH_SIZE,
): Promise<StagedRetirementAuditMetrics> {
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > STAGED_RETIREMENT_AUDIT_BATCH_SIZE) {
    throw new Error('Invalid staged document retirement audit worker batch size')
  }

  const metrics = emptyMetrics()
  const claims = await rpcRows(client, 'claim_staged_document_retirement_audit_batch', {
    p_org_id: orgId,
    p_batch_size: batchSize,
  })

  for (const claim of claims) {
    if (!hasOpaqueClaim(claim)) {
      metrics.skipped += 1
      if (typeof claim.code === 'string') count(metrics, claim.code)
      continue
    }
    metrics.claimed += 1
    const grant = await rpcRow(client, 'get_staged_document_retirement_audit_grant', {
      p_org_id: orgId,
      p_legacy_staged_document_id: claim.legacy_staged_document_id,
      p_audit_lease_token: claim.audit_lease_token,
    })
    if (!grant || !hasAuditGrant(grant)) {
      metrics.skipped += 1
      if (typeof grant?.code === 'string') count(metrics, grant.code)
      continue
    }

    let source: DownloadObservation
    try {
      source = await observeDownload(client, grant.source_bucket_id, grant.source_object_key)
    } catch {
      source = null
    }
    if (source === null) {
      metrics.retryable += 1
      count(metrics, 'source_retryable')
      continue
    }

    let outcome: StagedRetirementAuditOutcome
    let destination: DownloadObservation | undefined
    if (!source.found) {
      outcome = 'source_missing'
    } else if (source.byteSize !== grant.expected_byte_size || source.sha256 !== grant.expected_sha256) {
      outcome = 'source_observation_conflict'
    } else {
      try {
        destination = await observeDownload(client, grant.destination_bucket_id, grant.destination_object_key)
      } catch {
        destination = null
      }
      if (destination === null) {
        metrics.retryable += 1
        count(metrics, 'destination_retryable')
        continue
      }
      if (!destination.found) outcome = 'destination_missing'
      else if (destination.byteSize !== grant.expected_byte_size
        || destination.sha256 !== grant.expected_sha256
        || destination.byteSize !== source.byteSize
        || destination.sha256 !== source.sha256) outcome = 'destination_observation_conflict'
      else outcome = 'verified_equal'
    }

    const recorded = await rpcRow(client, 'record_staged_document_retirement_audit', {
      p_org_id: orgId,
      p_legacy_staged_document_id: claim.legacy_staged_document_id,
      p_audit_lease_token: claim.audit_lease_token,
      p_outcome: outcome,
      p_source_observed_bytes: outcome === 'verified_equal' && source.found ? source.byteSize : null,
      p_source_sha256: outcome === 'verified_equal' && source.found ? source.sha256 : null,
      p_destination_observed_bytes: outcome === 'verified_equal' && destination?.found ? destination.byteSize : null,
      p_destination_sha256: outcome === 'verified_equal' && destination?.found ? destination.sha256 : null,
    })
    const code = typeof recorded?.code === 'string' ? recorded.code : 'no_result'
    count(metrics, code)
    if (code === 'verified_equal') metrics.verified += 1
    else if (code === 'lease_not_held'
      || code === 'source_missing'
      || code === 'destination_missing'
      || code === 'source_observation_conflict'
      || code === 'destination_observation_conflict') metrics.skipped += 1
    else metrics.retryable += 1
  }

  return metrics
}
