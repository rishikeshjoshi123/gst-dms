import { createHash } from 'node:crypto'

import {
  STAGED_BACKFILL_MAX_OBJECT_BYTES,
  observeStagedDocumentBytes,
  type StagedBackfillClient,
} from './staged-backfill-verifier'

export const STAGED_BACKFILL_TRANSFER_BATCH_SIZE = 10

type RpcRow = Record<string, unknown>

export type StagedBackfillTransferMetrics = {
  claimed: number
  transferred: number
  retryable: number
  skipped: number
  outcomes: Record<string, number>
}

type TransferStorageClient = {
  from(bucket: string): {
    download(path: string): Promise<{ data: Blob | null; error: unknown }>
    upload(path: string, body: Blob, options: { contentType: 'application/pdf'; upsert: false }): Promise<{ error: unknown }>
  }
}

export type StagedBackfillTransferClient = Omit<StagedBackfillClient, 'storage'> & {
  storage: TransferStorageClient
}

function emptyMetrics(): StagedBackfillTransferMetrics {
  return { claimed: 0, transferred: 0, retryable: 0, skipped: 0, outcomes: {} }
}

function count(metrics: StagedBackfillTransferMetrics, code: string) {
  metrics.outcomes[code] = (metrics.outcomes[code] ?? 0) + 1
}

async function rpcRows(client: StagedBackfillTransferClient, name: string, args: Record<string, unknown>): Promise<RpcRow[]> {
  const result = await client.rpc(name, args)
  if (result.error) throw new Error('Staged document backfill service operation unavailable')
  return Array.isArray(result.data) ? result.data.filter((row): row is RpcRow => !!row && typeof row === 'object') : []
}

async function rpcRow(client: StagedBackfillTransferClient, name: string, args: Record<string, unknown>) {
  return (await rpcRows(client, name, args))[0] ?? null
}

function isMissingStorageError(error: unknown) {
  if (!error || typeof error !== 'object') return false
  const candidate = error as { status?: unknown; statusCode?: unknown; code?: unknown }
  return String(candidate.status) === '404' || String(candidate.statusCode) === '404' || candidate.code === '404'
}

function hasOpaqueClaim(row: RpcRow): row is RpcRow & {
  code: 'transfer_pending'
  legacy_staged_document_id: string
  transfer_lease_token: string
} {
  return row.code === 'transfer_pending'
    && typeof row.legacy_staged_document_id === 'string'
    && typeof row.transfer_lease_token === 'string'
}

function hasTransferGrant(row: RpcRow): row is RpcRow & {
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

async function bytesFrom(blob: Blob) {
  return new Uint8Array(await blob.arrayBuffer())
}

async function observeDestination(blob: Blob) {
  const bytes = await bytesFrom(blob)
  if (bytes.byteLength > STAGED_BACKFILL_MAX_OBJECT_BYTES) return null
  return {
    observedBytes: bytes.byteLength,
    sha256: createHash('sha256').update(bytes).digest('hex'),
  }
}

async function downloadDestination(
  client: StagedBackfillTransferClient,
  bucket: string,
  objectKey: string,
): Promise<{ found: true; observation: { observedBytes: number; sha256: string } } | { found: false } | null> {
  const downloaded = await client.storage.from(bucket).download(objectKey)
  if (downloaded.error) return isMissingStorageError(downloaded.error) ? { found: false } : null
  if (!downloaded.data) return null
  const observation = await observeDestination(downloaded.data)
  return observation ? { found: true, observation } : null
}

/**
 * Move a bounded serial batch from verified legacy staging to its preallocated
 * canonical asset keys. This accepts only an organisation id: both storage
 * paths and the expected source observation come from a fresh transfer grant.
 */
export async function transferStagedDocumentBackfillOrganisation(
  client: StagedBackfillTransferClient,
  orgId: string,
  batchSize = STAGED_BACKFILL_TRANSFER_BATCH_SIZE,
): Promise<StagedBackfillTransferMetrics> {
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > STAGED_BACKFILL_TRANSFER_BATCH_SIZE) {
    throw new Error('Invalid staged document backfill transfer worker batch size')
  }

  const metrics = emptyMetrics()
  const claims = await rpcRows(client, 'claim_staged_document_backfill_transfer_batch', {
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
    const grant = await rpcRow(client, 'get_staged_document_backfill_transfer_grant', {
      p_org_id: orgId,
      p_legacy_staged_document_id: claim.legacy_staged_document_id,
      p_transfer_lease_token: claim.transfer_lease_token,
    })
    if (!grant || !hasTransferGrant(grant)) {
      metrics.skipped += 1
      if (typeof grant?.code === 'string') count(metrics, grant.code)
      continue
    }

    let sourceBlob: Blob
    let sourceBytes: Uint8Array
    let source: Awaited<ReturnType<typeof observeStagedDocumentBytes>>
    try {
      const downloaded = await client.storage.from(grant.source_bucket_id).download(grant.source_object_key)
      if (downloaded.error || !downloaded.data) {
        metrics.retryable += 1
        count(metrics, 'source_retryable')
        continue
      }
      sourceBlob = downloaded.data
      sourceBytes = await bytesFrom(sourceBlob)
      source = await observeStagedDocumentBytes(sourceBytes)
    } catch {
      metrics.retryable += 1
      count(metrics, 'source_retryable')
      continue
    }
    if (source.sourceResult !== 'valid_pdf'
      || source.observedBytes !== grant.expected_byte_size
      || source.sha256 !== grant.expected_sha256
      || !source.pageCount) {
      // The existing verification observation no longer matches the fresh,
      // trusted source. Do not upload or finalise anything.
      metrics.skipped += 1
      count(metrics, 'source_observation_conflict')
      continue
    }

    let destination: Awaited<ReturnType<typeof downloadDestination>>
    try {
      destination = await downloadDestination(client, grant.destination_bucket_id, grant.destination_object_key)
    } catch {
      destination = null
    }
    if (destination === null) {
      metrics.retryable += 1
      count(metrics, 'destination_retryable')
      continue
    }
    if (!destination.found) {
      try {
        // A predetermined immutable object key is never overwritten. A retry
        // after a prior worker upload re-reads the key below instead.
        const uploaded = await client.storage.from(grant.destination_bucket_id).upload(
          grant.destination_object_key,
          sourceBlob,
          { contentType: 'application/pdf', upsert: false },
        )
        if (uploaded.error) {
          // A conflict may mean a prior attempt reached Storage before its
          // lease expired. Re-read and prove the destination rather than retry
          // an overwrite or treating an opaque provider error as success.
        }
      } catch {
        // The independent post-copy read below is the sole authority.
      }
      try {
        destination = await downloadDestination(client, grant.destination_bucket_id, grant.destination_object_key)
      } catch {
        destination = null
      }
      if (destination === null || !destination.found) {
        metrics.retryable += 1
        count(metrics, 'destination_retryable')
        continue
      }
    }

    const recorded = await rpcRow(client, 'complete_staged_document_backfill_transfer', {
      p_org_id: orgId,
      p_legacy_staged_document_id: claim.legacy_staged_document_id,
      p_transfer_lease_token: claim.transfer_lease_token,
      p_source_observed_bytes: source.observedBytes,
      p_source_sha256: source.sha256,
      p_source_page_count: source.pageCount,
      p_destination_observed_bytes: destination.observation.observedBytes,
      p_destination_sha256: destination.observation.sha256,
    })
    const code = typeof recorded?.code === 'string' ? recorded.code : 'no_result'
    count(metrics, code)
    if (code === 'transferred' || code === 'already_transferred') metrics.transferred += 1
    else if (code === 'lease_not_held' || code === 'duplicate_reference') metrics.skipped += 1
    else metrics.retryable += 1
  }

  return metrics
}
