import { schedules } from '@trigger.dev/sdk/v3'

import {
  STAGED_BACKFILL_BATCH_SIZE,
  verifyStagedDocumentBackfillOrganisation,
  type StagedBackfillClient,
  type StagedBackfillMetrics,
} from '@/lib/documents/staged-backfill-verifier'
import {
  STAGED_BACKFILL_TRANSFER_BATCH_SIZE,
  transferStagedDocumentBackfillOrganisation,
  type StagedBackfillTransferClient,
  type StagedBackfillTransferMetrics,
} from '@/lib/documents/staged-backfill-transfer'

const MAX_ORGANISATIONS_PER_RUN = 10
const MAX_TRANSFER_ORGANISATIONS_PER_RUN = 5

type BackfillReportRow = {
  org_id: string
  classification_complete: boolean
  transfer_pending_count?: number
}

function mergeMetrics(total: StagedBackfillMetrics, next: StagedBackfillMetrics) {
  total.claimed += next.claimed
  total.classified += next.classified
  total.retryable += next.retryable
  total.skipped += next.skipped
  for (const [code, count] of Object.entries(next.outcomes)) total.outcomes[code] = (total.outcomes[code] ?? 0) + count
}

function mergeTransferMetrics(total: StagedBackfillTransferMetrics, next: StagedBackfillTransferMetrics) {
  total.claimed += next.claimed
  total.transferred += next.transferred
  total.retryable += next.retryable
  total.skipped += next.skipped
  for (const [code, count] of Object.entries(next.outcomes)) total.outcomes[code] = (total.outcomes[code] ?? 0) + count
}

// This scheduled operation is intentionally verifier-only. It does not create
// Intake, copy/delete a staged object, alter legacy reads, or release a
// transfer fence. The verifier module accepts only an organisation id; each
// object key is resolved in-process from a short-lived service-only grant.
export const verifyStagedDocumentBackfill = schedules.task({
  id: 'verify-staged-document-backfill',
  cron: { pattern: '*/5 * * * *', timezone: 'UTC' },
  queue: { concurrencyLimit: 1 },
  retry: { maxAttempts: 3, minTimeoutInMs: 1_000, maxTimeoutInMs: 15_000, factor: 2 },
  maxDuration: 300,
  run: async () => {
    const { createServiceClient } = await import('@/lib/supabase/server')
    const client = createServiceClient() as unknown as StagedBackfillClient & {
      from(table: 'staged_document_backfill_reports'): {
        select(columns: 'org_id, classification_complete'): {
          eq(column: 'classification_complete', value: false): { limit(limit: number): Promise<{ data: BackfillReportRow[] | null; error: { message: string } | null }> }
        }
      }
    }
    const reports = await client
      .from('staged_document_backfill_reports')
      .select('org_id, classification_complete')
      .eq('classification_complete', false)
      .limit(MAX_ORGANISATIONS_PER_RUN)
    if (reports.error) throw new Error('Staged document backfill reports unavailable')

    const total: StagedBackfillMetrics = { claimed: 0, classified: 0, retryable: 0, skipped: 0, outcomes: {} }
    let organisations = 0
    for (const report of reports.data ?? []) {
      if (typeof report.org_id !== 'string' || report.classification_complete) continue
      mergeMetrics(total, await verifyStagedDocumentBackfillOrganisation(client, report.org_id, STAGED_BACKFILL_BATCH_SIZE))
      organisations += 1
    }

    // Trigger receives bounded aggregate metrics only; source IDs, object keys,
    // hashes, bytes, content, and storage/parser errors never leave the worker.
    return { organisations, ...total }
  },
})

// The transfer runs separately from verification and is intentionally serial.
// It accepts no task payload: the database selects organisations and the
// per-item transfer module receives all paths only through a fresh lease grant.
export const transferStagedDocumentBackfill = schedules.task({
  id: 'transfer-staged-document-backfill',
  cron: { pattern: '*/10 * * * *', timezone: 'UTC' },
  queue: { concurrencyLimit: 1 },
  retry: { maxAttempts: 3, minTimeoutInMs: 1_000, maxTimeoutInMs: 15_000, factor: 2 },
  maxDuration: 300,
  run: async () => {
    const { createServiceClient } = await import('@/lib/supabase/server')
    const client = createServiceClient() as unknown as StagedBackfillTransferClient & {
      from(table: 'staged_document_backfill_reports'): {
        select(columns: 'org_id, transfer_pending_count'): {
          gt(column: 'transfer_pending_count', value: number): { limit(limit: number): Promise<{ data: BackfillReportRow[] | null; error: { message: string } | null }> }
        }
      }
    }
    const reports = await client
      .from('staged_document_backfill_reports')
      .select('org_id, transfer_pending_count')
      .gt('transfer_pending_count', 0)
      .limit(MAX_TRANSFER_ORGANISATIONS_PER_RUN)
    if (reports.error) throw new Error('Staged document transfer reports unavailable')

    const total: StagedBackfillTransferMetrics = { claimed: 0, transferred: 0, retryable: 0, skipped: 0, outcomes: {} }
    let organisations = 0
    for (const report of reports.data ?? []) {
      if (typeof report.org_id !== 'string' || report.transfer_pending_count !== undefined && report.transfer_pending_count <= 0) continue
      mergeTransferMetrics(total, await transferStagedDocumentBackfillOrganisation(client, report.org_id, STAGED_BACKFILL_TRANSFER_BATCH_SIZE))
      organisations += 1
    }

    // Aggregate counts only: never return object keys, source IDs, hashes,
    // byte counts, content, or provider/parser errors to task logs.
    return { organisations, ...total }
  },
})
