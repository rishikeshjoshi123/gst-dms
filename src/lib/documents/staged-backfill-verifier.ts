import { createHash } from 'node:crypto'

import { validatePdfBytes, type ValidationOutcome } from './validation'

/**
 * This module is imported only by the Trigger worker.  It intentionally takes
 * no path from a caller: Storage can be reached only after the database issues
 * a short-lived source grant for an opaque staged-document id.
 */
export const STAGED_BACKFILL_BATCH_SIZE = 25
export const STAGED_BACKFILL_MAX_OBJECT_BYTES = 100 * 1024 * 1024

export type StagedBackfillSourceResult =
  | 'valid_pdf'
  | 'missing'
  | 'unreadable'
  | 'malformed_pdf'
  | 'encrypted_pdf'
  | 'non_pdf'
  | 'oversize'

type RpcRow = Record<string, unknown>

export type StagedBackfillClient = {
  rpc(name: string, args: Record<string, unknown>): Promise<{
    data: unknown
    error: { message: string } | null
  }>
  storage: {
    from(bucket: string): {
      download(path: string): Promise<{ data: Blob | null; error: unknown }>
    }
  }
}

export type StagedBackfillMetrics = {
  claimed: number
  classified: number
  retryable: number
  skipped: number
  outcomes: Record<string, number>
}

function emptyMetrics(): StagedBackfillMetrics {
  return { claimed: 0, classified: 0, retryable: 0, skipped: 0, outcomes: {} }
}

function count(metrics: StagedBackfillMetrics, code: string) {
  metrics.outcomes[code] = (metrics.outcomes[code] ?? 0) + 1
}

async function rpcRows(client: StagedBackfillClient, name: string, args: Record<string, unknown>): Promise<RpcRow[]> {
  const result = await client.rpc(name, args)
  if (result.error) throw new Error('Staged document backfill service operation unavailable')
  return Array.isArray(result.data) ? result.data.filter((row): row is RpcRow => !!row && typeof row === 'object') : []
}

async function rpcRow(client: StagedBackfillClient, name: string, args: Record<string, unknown>) {
  return (await rpcRows(client, name, args))[0] ?? null
}

function isPdfSignature(bytes: Uint8Array) {
  // ISO 32000 permits a binary marker before the header, but requires the
  // header within the first 1,024 bytes. Do not trust Storage MIME metadata.
  const header = new TextDecoder('latin1').decode(bytes.subarray(0, 1024))
  return header.includes('%PDF-')
}

function mapValidationOutcome(outcome: ValidationOutcome): StagedBackfillSourceResult {
  switch (outcome) {
    case 'ready': return 'valid_pdf'
    case 'encrypted_pdf': return 'encrypted_pdf'
    case 'invalid_pdf': return 'malformed_pdf'
    // A same-buffer validation failure is not a valid PDF observation. This is
    // deliberately distinct from a missing Storage object.
    case 'validation_failed': return 'unreadable'
    case 'storage_missing': return 'missing'
  }
}

export async function observeStagedDocumentBytes(
  bytes: Uint8Array,
  validate: (bytes: Uint8Array, expectedBytes: number) => Promise<{ outcome: ValidationOutcome; pageCount: number | null }> = validatePdfBytes,
  maxBytes = STAGED_BACKFILL_MAX_OBJECT_BYTES,
): Promise<{ sourceResult: StagedBackfillSourceResult; observedBytes?: number; sha256?: string; pageCount?: number }> {
  const observedBytes = bytes.byteLength
  const sha256 = createHash('sha256').update(bytes).digest('hex')

  if (observedBytes > maxBytes) return { sourceResult: 'oversize' }
  if (!isPdfSignature(bytes)) return { sourceResult: 'non_pdf' }

  const validation = await validate(bytes, observedBytes)
  if (validation.outcome !== 'ready') return { sourceResult: mapValidationOutcome(validation.outcome) }
  return { sourceResult: 'valid_pdf', observedBytes, sha256, pageCount: validation.pageCount ?? undefined }
}

function isMissingStorageError(error: unknown) {
  if (!error || typeof error !== 'object') return false
  const candidate = error as { status?: unknown; statusCode?: unknown; code?: unknown }
  return String(candidate.status) === '404' || String(candidate.statusCode) === '404' || candidate.code === '404'
}

function hasOpaqueClaim(row: RpcRow): row is RpcRow & {
  code: 'verification_required'
  legacy_staged_document_id: string
  verification_lease_token: string
} {
  return row.code === 'verification_required'
    && typeof row.legacy_staged_document_id === 'string'
    && typeof row.verification_lease_token === 'string'
}

/**
 * Claim and verify one bounded organisation batch. Returned metrics contain no
 * source IDs, paths, bytes, hashes, filenames, or parser/storage errors.
 */
export async function verifyStagedDocumentBackfillOrganisation(
  client: StagedBackfillClient,
  orgId: string,
  batchSize = STAGED_BACKFILL_BATCH_SIZE,
): Promise<StagedBackfillMetrics> {
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > STAGED_BACKFILL_BATCH_SIZE) {
    throw new Error('Invalid staged document backfill worker batch size')
  }

  const metrics = emptyMetrics()
  const claims = await rpcRows(client, 'claim_staged_document_backfill_batch', {
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
    const sourceGrant = await rpcRow(client, 'get_staged_document_backfill_source_grant', {
      p_org_id: orgId,
      p_legacy_staged_document_id: claim.legacy_staged_document_id,
      p_verification_lease_token: claim.verification_lease_token,
    })

    // A lease can expire or an old-flow fence can change between claim and
    // grant. Do not record a fabricated result; a later claim will retry or
    // terminally classify the source in SQL.
    if (sourceGrant?.code !== 'ok' || typeof sourceGrant.bucket_id !== 'string' || typeof sourceGrant.object_key !== 'string') {
      metrics.skipped += 1
      if (typeof sourceGrant?.code === 'string') count(metrics, sourceGrant.code)
      continue
    }

    let observation: { sourceResult: StagedBackfillSourceResult; observedBytes?: number; sha256?: string }
    try {
      // bucket_id/object_key come only from the leased database grant above.
      const downloaded = await client.storage.from(sourceGrant.bucket_id).download(sourceGrant.object_key)
      if (downloaded.error) {
        if (isMissingStorageError(downloaded.error)) observation = { sourceResult: 'missing' }
        else {
          metrics.retryable += 1
          count(metrics, 'storage_retryable')
          continue
        }
      } else if (!downloaded.data) {
        metrics.retryable += 1
        count(metrics, 'storage_retryable')
        continue
      } else {
        observation = await observeStagedDocumentBytes(new Uint8Array(await downloaded.data.arrayBuffer()))
      }
    } catch {
      // Network/worker faults are retried through the expiry-safe database
      // lease; never promote a transient failure to missing or log its detail.
      metrics.retryable += 1
      count(metrics, 'storage_retryable')
      continue
    }

    const recorded = await rpcRow(client, 'record_staged_document_backfill_verification', {
      p_org_id: orgId,
      p_legacy_staged_document_id: claim.legacy_staged_document_id,
      p_verification_lease_token: claim.verification_lease_token,
      p_source_result: observation.sourceResult,
      p_observed_bytes: observation.observedBytes ?? null,
      p_sha256: observation.sha256 ?? null,
    })
    const code = typeof recorded?.code === 'string' ? recorded.code : 'no_result'
    count(metrics, code)
    if (code === 'lease_not_held') metrics.skipped += 1
    else metrics.classified += 1
  }

  return metrics
}
