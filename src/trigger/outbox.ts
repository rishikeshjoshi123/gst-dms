import { schedules, task } from '@trigger.dev/sdk'
import { createSupabaseOutboxTransport } from '@/lib/outbox/supabase-transport'
import { dispatchLeasedEvents, type DocumentLifecycleEnvelope } from '@/lib/outbox/dispatcher'
import { runValidationWorker, safeProcessingOutcome } from '@/lib/documents/orchestration'
import { validatePdfBytes } from '@/lib/documents/validation'

type RpcClient = {
  rpc(name: string, args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>
  storage: {
    from(bucket: string): {
      download(path: string): Promise<{ data: Blob | null; error: unknown }>
      remove(paths: string[]): Promise<{ data: unknown; error: unknown }>
    }
  }
}
const rpc = async (client: RpcClient, name: string, args: Record<string, unknown>) => {
  const result = await client.rpc(name, args)
  if (result.error) throw new Error('Document orchestration RPC unavailable')
  return (result.data as Array<Record<string, unknown>> | null)?.[0] ?? null
}

export const documentLifecycleEvent = task({
  id: 'document-lifecycle-event',
  retry: { maxAttempts: 5 },
  queue: { concurrencyLimit: 4 },
  run: async (payload: Omit<DocumentLifecycleEnvelope, 'leaseToken'>, { ctx }) => {
    const { createServiceClient } = await import('@/lib/supabase/server')
    const client = createServiceClient() as unknown as RpcClient
    if (payload.eventKind === 'document.upload_validation_requested.v1') {
      const claim = await rpc(client, 'claim_document_validation_work', { p_event_id: payload.eventId })
      if (!claim || claim.code !== 'claimed') return { accepted: true, routed: 'validation', outcome: String(claim?.code ?? 'no_work') }
      const result = await runValidationWorker({
        expectedBytes: Number(claim.expected_bytes),
        download: async () => {
          const file = await client.storage.from(String(claim.bucket_id)).download(String(claim.object_key))
          return file.data ? new Uint8Array(await file.data.arrayBuffer()) : null
        },
        finish: (outcome, pageCount) => rpc(client, 'finish_document_validation_work', { p_source_run_id: claim.source_run_id, p_lease_token: claim.lease_token, p_outcome: outcome, p_page_count: pageCount }),
      }, validatePdfBytes)
      return { accepted: true, routed: 'validation', outcome: result.outcome }
    }
    if (payload.eventKind === 'document.intake_validated.v1') {
      const intakeId = payload.payload.intake_id
      if (typeof intakeId !== 'string') return { accepted: true, routed: 'intended-assignment', outcome: 'invalid_event' }
      const assignment = await rpc(client, 'auto_assign_intended_matter_intake', {
        p_intake_id: intakeId,
        p_validation_event_id: payload.eventId,
      })
      return { accepted: true, routed: 'intended-assignment', outcome: String(assignment?.code ?? 'no_work') }
    }
    if (payload.eventKind === 'document.processing_requested.v1') {
      const claim = await rpc(client, 'claim_document_processing_work', { p_event_id: payload.eventId, p_trigger_run_id: ctx.run.id })
      if (!claim || claim.code !== 'claimed') return { accepted: true, routed: 'processing', outcome: String(claim?.code ?? 'no_work') }
      let outcome: ReturnType<typeof safeProcessingOutcome> = 'failed'
      try {
        const { processDocument } = await import('./jobs')
        const child = await processDocument.triggerAndWait({ docId: String(claim.document_id), matterId: String(claim.matter_id), orgId: payload.orgId, storagePath: String(claim.object_key), uploadedBy: String(claim.actor_id) }, { idempotencyKey: `document-processing:${payload.eventId}:${claim.document_version_id}`, concurrencyKey: payload.orgId })
        outcome = child.ok ? safeProcessingOutcome(child.output?.status) : 'failed'
      } catch {
        outcome = 'failed'
      }
      await rpc(client, 'finish_document_processing_work', { p_processing_run_id: claim.processing_run_id, p_lease_token: claim.lease_token, p_outcome: outcome })
      return { accepted: true, routed: 'processing', outcome }
    }
    return { accepted: true, routed: 'observed', eventId: payload.eventId, eventKind: payload.eventKind }
  },
})

export const dispatchDocumentOutbox = schedules.task({
  id: 'dispatch-document-outbox',
  cron: { pattern: '* * * * *', timezone: 'UTC' },
  queue: { concurrencyLimit: 1 },
  run: async () => dispatchLeasedEvents(createSupabaseOutboxTransport(), {
    trigger: (envelope, options) => documentLifecycleEvent.trigger(envelope, options),
  }, { maxBatches: 4 }),
})

// A successful gateway delivery only proves Trigger accepted the event. This
// The reconciler replays only expired validation leases. Legacy document
// processing is fenced into a durable recovery case because its downstream
// effects predate run-level idempotency.
export const reconcileDocumentLifecycleWork = schedules.task({
  id: 'reconcile-document-lifecycle-work',
  cron: { pattern: '*/5 * * * *', timezone: 'UTC' },
  run: async () => {
    const { createServiceClient } = await import('@/lib/supabase/server')
    const client = createServiceClient() as unknown as RpcClient
    const result = await client.rpc('reconcile_document_processing_work', { p_batch_size: 100 })
    if (result.error) throw new Error('Document lifecycle reconciliation unavailable')
    return (result.data as Array<Record<string, unknown>> | null)?.[0] ?? { validation_requeued: 0, processing_requeued: 0 }
  },
})

// Terminal/expired intake rows are retained for audit. Their object is removed
// separately so quota reflects actual retained bytes until Storage confirms the
// delete; failed deletes are intentionally left for a later retry.
export const cleanTerminalDocumentAssets = schedules.task({
  id: 'clean-terminal-document-assets',
  cron: { pattern: '*/5 * * * *', timezone: 'UTC' },
  run: async () => {
    const { createServiceClient } = await import('@/lib/supabase/server')
    const client = createServiceClient() as unknown as RpcClient
    const result = await client.rpc('claim_document_asset_storage_deletion_work', { p_batch_size: 100 })
    if (result.error) throw new Error('Terminal document asset cleanup unavailable')

    let deleted = 0
    let failed = 0
    for (const asset of (result.data as Array<Record<string, unknown>> | null) ?? []) {
      const removal = await client.storage.from(String(asset.bucket_id)).remove([String(asset.object_key)])
      const outcome = removal.error ? 'failed' : 'deleted'
      const finish = await rpc(client, 'finish_document_asset_storage_deletion_work', {
        p_asset_id: asset.asset_id,
        p_lease_token: asset.lease_token,
        p_outcome: outcome,
      })
      if (finish?.code === 'deleted') deleted += 1
      if (finish?.code === 'failed') failed += 1
    }
    return { deleted, failed }
  },
})
