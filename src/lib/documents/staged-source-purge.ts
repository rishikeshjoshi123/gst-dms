import { observeStagedDocumentBytes, type StagedBackfillClient } from './staged-backfill-verifier'

export const STAGED_SOURCE_PURGE_BATCH_SIZE = 5

type RpcRow = Record<string, unknown>

export type StagedSourcePurgeMetrics = {
  claimed: number
  deleted: number
  recovery: number
  retryable: number
  skipped: number
  outcomes: Record<string, number>
}

type PurgeStorageClient = {
  from(bucket: string): {
    download(path: string): Promise<{ data: Blob | null; error: unknown }>
    remove(paths: string[]): Promise<{ error: unknown }>
  }
}

export type StagedSourcePurgeClient = Omit<StagedBackfillClient, 'storage'> & {
  storage: PurgeStorageClient
}

type ValidObservation = { byteSize: number; sha256: string; pageCount: number }
type DownloadObservation = { kind: 'valid'; value: ValidObservation } | { kind: 'missing' } | { kind: 'invalid' } | null

function emptyMetrics(): StagedSourcePurgeMetrics {
  return { claimed: 0, deleted: 0, recovery: 0, retryable: 0, skipped: 0, outcomes: {} }
}

function count(metrics: StagedSourcePurgeMetrics, code: string) {
  metrics.outcomes[code] = (metrics.outcomes[code] ?? 0) + 1
}

async function rpcRows(client: StagedSourcePurgeClient, name: string, args: Record<string, unknown>): Promise<RpcRow[]> {
  const result = await client.rpc(name, args)
  if (result.error) throw new Error('Staged source purge service operation unavailable')
  return Array.isArray(result.data) ? result.data.filter((row): row is RpcRow => !!row && typeof row === 'object') : []
}

async function rpcRow(client: StagedSourcePurgeClient, name: string, args: Record<string, unknown>) {
  return (await rpcRows(client, name, args))[0] ?? null
}

function isMissingStorageError(error: unknown) {
  if (!error || typeof error !== 'object') return false
  const candidate = error as { status?: unknown; statusCode?: unknown; code?: unknown }
  return String(candidate.status) === '404' || String(candidate.statusCode) === '404' || candidate.code === '404'
}

function hasOpaqueClaim(row: RpcRow): row is RpcRow & {
  code: 'purge_required'
  legacy_staged_document_id: string
  purge_lease_token: string
} {
  return row.code === 'purge_required'
    && typeof row.legacy_staged_document_id === 'string'
    && typeof row.purge_lease_token === 'string'
}

function hasPurgeGrant(row: RpcRow): row is RpcRow & {
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
    && row.expected_byte_size > 0
    && typeof row.expected_sha256 === 'string'
    && /^[0-9a-f]{64}$/.test(row.expected_sha256)
}

async function observeDownload(
  client: StagedSourcePurgeClient,
  bucket: string,
  objectKey: string,
): Promise<DownloadObservation> {
  const downloaded = await client.storage.from(bucket).download(objectKey)
  if (downloaded.error) return isMissingStorageError(downloaded.error) ? { kind: 'missing' } : null
  if (!downloaded.data) return null
  const observation = await observeStagedDocumentBytes(new Uint8Array(await downloaded.data.arrayBuffer()))
  if (observation.sourceResult !== 'valid_pdf'
    || !observation.observedBytes
    || !observation.sha256
    || !observation.pageCount) return { kind: 'invalid' }
  return {
    kind: 'valid',
    value: { byteSize: observation.observedBytes, sha256: observation.sha256, pageCount: observation.pageCount },
  }
}

async function recordRecovery(
  client: StagedSourcePurgeClient,
  orgId: string,
  legacyStagedDocumentId: string,
  purgeLeaseToken: string,
  recoveryCode: string,
  metrics: StagedSourcePurgeMetrics,
) {
  const result = await rpcRow(client, 'record_staged_document_source_purge_recovery', {
    p_org_id: orgId,
    p_legacy_staged_document_id: legacyStagedDocumentId,
    p_purge_lease_token: purgeLeaseToken,
    p_recovery_code: recoveryCode,
  })
  const code = typeof result?.code === 'string' ? result.code : 'no_result'
  count(metrics, code)
  if (code === 'recovery_required') metrics.recovery += 1
  else metrics.skipped += 1
}

/**
 * Purges only a redundant staging object after an immediately fresh,
 * lease-bound source/destination/PDF proof.  The function receives only an
 * organisation ID; every Storage key comes from a live database grant, never
 * task input.  Metrics intentionally contain counts and safe codes only.
 */
export async function purgeStagedDocumentSourcesForOrganisation(
  client: StagedSourcePurgeClient,
  orgId: string,
  batchSize = STAGED_SOURCE_PURGE_BATCH_SIZE,
): Promise<StagedSourcePurgeMetrics> {
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > STAGED_SOURCE_PURGE_BATCH_SIZE) {
    throw new Error('Invalid staged source purge worker batch size')
  }

  const metrics = emptyMetrics()
  const claims = await rpcRows(client, 'claim_staged_document_source_purge_batch', {
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

    const grant = await rpcRow(client, 'get_staged_document_source_purge_grant', {
      p_org_id: orgId,
      p_legacy_staged_document_id: claim.legacy_staged_document_id,
      p_purge_lease_token: claim.purge_lease_token,
    })
    if (!grant || !hasPurgeGrant(grant)) {
      if (grant?.code === 'database_inconsistent') {
        await recordRecovery(client, orgId, claim.legacy_staged_document_id, claim.purge_lease_token, 'database_inconsistent', metrics)
      } else {
        metrics.skipped += 1
        if (typeof grant?.code === 'string') count(metrics, grant.code)
      }
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
    if (source.kind === 'missing') {
      // A 404 can confirm a prior durable intent after response loss.  A first
      // observation of absence is a contradiction and is kept for recovery.
      const confirmed = await rpcRow(client, 'confirm_staged_document_source_purge', {
        p_org_id: orgId,
        p_legacy_staged_document_id: claim.legacy_staged_document_id,
        p_purge_lease_token: claim.purge_lease_token,
        p_confirmation: 'storage_missing_after_intent',
      })
      const code = typeof confirmed?.code === 'string' ? confirmed.code : 'no_result'
      if (code === 'deleted' || code === 'already_deleted') {
        metrics.deleted += 1
        count(metrics, code)
      } else if (code === 'intent_not_recorded') {
        await recordRecovery(client, orgId, claim.legacy_staged_document_id, claim.purge_lease_token, 'source_missing_before_intent', metrics)
      } else {
        metrics.skipped += 1
        count(metrics, code)
      }
      continue
    }
    if (source.kind === 'invalid') {
      await recordRecovery(client, orgId, claim.legacy_staged_document_id, claim.purge_lease_token, 'source_pdf_invalid', metrics)
      continue
    }
    if (source.value.byteSize !== grant.expected_byte_size || source.value.sha256 !== grant.expected_sha256) {
      await recordRecovery(client, orgId, claim.legacy_staged_document_id, claim.purge_lease_token, 'source_observation_conflict', metrics)
      continue
    }

    let destination: DownloadObservation
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
    if (destination.kind === 'missing') {
      await recordRecovery(client, orgId, claim.legacy_staged_document_id, claim.purge_lease_token, 'destination_missing', metrics)
      continue
    }
    if (destination.kind === 'invalid') {
      await recordRecovery(client, orgId, claim.legacy_staged_document_id, claim.purge_lease_token, 'destination_pdf_invalid', metrics)
      continue
    }
    if (destination.value.byteSize !== grant.expected_byte_size
      || destination.value.sha256 !== grant.expected_sha256
      || destination.value.byteSize !== source.value.byteSize
      || destination.value.sha256 !== source.value.sha256) {
      await recordRecovery(client, orgId, claim.legacy_staged_document_id, claim.purge_lease_token, 'destination_observation_conflict', metrics)
      continue
    }

    const intent = await rpcRow(client, 'record_staged_document_source_purge_intent', {
      p_org_id: orgId,
      p_legacy_staged_document_id: claim.legacy_staged_document_id,
      p_purge_lease_token: claim.purge_lease_token,
      p_source_observed_bytes: source.value.byteSize,
      p_source_sha256: source.value.sha256,
      p_source_page_count: source.value.pageCount,
      p_destination_observed_bytes: destination.value.byteSize,
      p_destination_sha256: destination.value.sha256,
      p_destination_page_count: destination.value.pageCount,
    })
    const intentCode = typeof intent?.code === 'string' ? intent.code : 'no_result'
    if (intentCode !== 'delete_intended') {
      if (intentCode === 'observation_conflict') {
        await recordRecovery(client, orgId, claim.legacy_staged_document_id, claim.purge_lease_token, 'database_inconsistent', metrics)
      } else {
        metrics.skipped += 1
        count(metrics, intentCode)
      }
      continue
    }

    // Fetch a second live grant after durable intent, immediately before the
    // external delete.  The worker still has no path from task input.
    const deleteGrant = await rpcRow(client, 'get_staged_document_source_purge_grant', {
      p_org_id: orgId,
      p_legacy_staged_document_id: claim.legacy_staged_document_id,
      p_purge_lease_token: claim.purge_lease_token,
    })
    if (!deleteGrant || !hasPurgeGrant(deleteGrant)) {
      if (deleteGrant?.code === 'database_inconsistent') {
        await recordRecovery(client, orgId, claim.legacy_staged_document_id, claim.purge_lease_token, 'database_inconsistent', metrics)
      } else if (deleteGrant?.code === 'guard_coverage_incomplete') {
        // Intent is already durable: a revoked coverage authority cannot leave
        // it ambiguous for a later worker to mistake as still deletable.
        await recordRecovery(client, orgId, claim.legacy_staged_document_id, claim.purge_lease_token, 'late_guard_blocker', metrics)
      } else if (deleteGrant?.code === 'not_eligible') {
        await recordRecovery(client, orgId, claim.legacy_staged_document_id, claim.purge_lease_token, 'late_eligibility_blocker', metrics)
      } else {
        metrics.skipped += 1
        if (typeof deleteGrant?.code === 'string') count(metrics, deleteGrant.code)
      }
      continue
    }

    let removed: { error: unknown }
    try {
      removed = await client.storage.from(deleteGrant.source_bucket_id).remove([deleteGrant.source_object_key])
    } catch {
      metrics.retryable += 1
      count(metrics, 'storage_delete_retryable')
      continue
    }
    if (removed.error && !isMissingStorageError(removed.error)) {
      metrics.retryable += 1
      count(metrics, 'storage_delete_retryable')
      continue
    }
    const confirmed = await rpcRow(client, 'confirm_staged_document_source_purge', {
      p_org_id: orgId,
      p_legacy_staged_document_id: claim.legacy_staged_document_id,
      p_purge_lease_token: claim.purge_lease_token,
      p_confirmation: removed.error ? 'storage_missing_after_intent' : 'storage_deleted',
    })
    const code = typeof confirmed?.code === 'string' ? confirmed.code : 'no_result'
    count(metrics, code)
    if (code === 'deleted' || code === 'already_deleted') metrics.deleted += 1
    else metrics.skipped += 1
  }

  return metrics
}
