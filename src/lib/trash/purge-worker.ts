export type TrashPurgeRpcClient = {
  rpc(name: string, args: Record<string, unknown>): Promise<{ data: unknown; error: unknown }>
  storage: {
    from(bucket: string): {
      remove(paths: string[]): Promise<{ data: unknown; error: unknown }>
    }
  }
}

type Row = Record<string, unknown>

function rows(value: unknown): Row[] {
  return Array.isArray(value) ? value.filter((item): item is Row => Boolean(item) && typeof item === 'object') : []
}

async function rpc(client: TrashPurgeRpcClient, name: string, args: Record<string, unknown>) {
  const result = await client.rpc(name, args)
  if (result.error) throw new Error('Trash permanent-delete authority unavailable')
  return rows(result.data)
}

export function isExplicitStorageNotFound(error: unknown) {
  if (!error || typeof error !== 'object') return false
  const value = error as { status?: unknown; statusCode?: unknown; code?: unknown }
  return String(value.status) === '404' || String(value.statusCode) === '404' || String(value.code) === '404'
}

/**
 * Drain a bounded set of durable purge jobs. Database leases own all work;
 * Storage receives only private locators returned after transactional proof.
 */
export async function runTrashPurgeBatch(client: TrashPurgeRpcClient) {
  await rpc(client, 'enqueue_due_trash_purges', { p_batch_size: 100 })
  const jobs = await rpc(client, 'claim_trash_purge_work', { p_batch_size: 10, p_lease_seconds: 600 })
  const results: Array<{ operationId: string; code: string }> = []

  for (const job of jobs) {
    const jobId = String(job.job_id)
    const operationId = String(job.operation_id)
    const jobLease = String(job.lease_token)
    const prepared = await rpc(client, 'prepare_trash_purge_database', {
      p_job_id: jobId,
      p_lease_token: jobLease,
    })
    const prepareCode = String(prepared[0]?.code ?? 'not_available')
    if (!['prepared', 'already_prepared'].includes(prepareCode)) {
      results.push({ operationId, code: prepareCode })
      continue
    }

    let storageFailure = false
    while (!storageFailure) {
      const deletions = await rpc(client, 'claim_trash_purge_storage_deletions', {
        p_job_id: jobId,
        p_job_lease_token: jobLease,
        p_batch_size: 25,
        p_lease_seconds: 600,
      })
      if (!deletions.length) break
      for (const deletion of deletions) {
        const removal = await client.storage.from(String(deletion.bucket_id)).remove([String(deletion.object_key)])
        const outcome = !removal.error || isExplicitStorageNotFound(removal.error) ? 'deleted' : 'failed'
        await rpc(client, 'finish_trash_purge_storage_deletion', {
          p_deletion_id: deletion.deletion_id,
          p_lease_token: deletion.lease_token,
          p_outcome: outcome,
        })
        if (outcome === 'failed') storageFailure = true
      }
    }

    const finished = await rpc(client, 'finish_trash_purge_attempt', {
      p_job_id: jobId,
      p_lease_token: jobLease,
    })
    results.push({ operationId, code: String(finished[0]?.code ?? 'not_available') })
  }
  return results
}
