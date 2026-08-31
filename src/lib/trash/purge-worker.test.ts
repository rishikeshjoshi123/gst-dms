import assert from 'node:assert/strict'
import test from 'node:test'

import { isExplicitStorageNotFound, runTrashPurgeBatch, type TrashPurgeRpcClient } from './purge-worker'

function clientFor(removeError: unknown = null) {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  let deletionClaim = 0
  const client: TrashPurgeRpcClient = {
    async rpc(name, args) {
      calls.push({ name, args })
      if (name === 'enqueue_due_trash_purges') return { data: [{ queued_count: 0 }], error: null }
      if (name === 'claim_trash_purge_work') return { data: [{ job_id: 'job', operation_id: 'operation', lease_token: 'job-lease' }], error: null }
      if (name === 'prepare_trash_purge_database') return { data: [{ code: 'prepared' }], error: null }
      if (name === 'claim_trash_purge_storage_deletions') {
        deletionClaim += 1
        return { data: deletionClaim === 1 ? [{ deletion_id: 'deletion', bucket_id: 'documents', object_key: 'private/key', lease_token: 'storage-lease' }] : [], error: null }
      }
      if (name === 'finish_trash_purge_storage_deletion') return { data: [{ code: args.p_outcome }], error: null }
      if (name === 'finish_trash_purge_attempt') return { data: [{ code: removeError && !isExplicitStorageNotFound(removeError) ? 'retryable' : 'purged' }], error: null }
      return { data: [], error: null }
    },
    storage: { from: () => ({ async remove() { return { data: null, error: removeError } } }) },
  }
  return { client, calls }
}

test('drains one durable job and treats explicit Storage not-found as reconciled success', async () => {
  const { client, calls } = clientFor({ statusCode: 404 })
  assert.deepEqual(await runTrashPurgeBatch(client), [{ operationId: 'operation', code: 'purged' }])
  assert.equal(calls.find((call) => call.name === 'finish_trash_purge_storage_deletion')?.args.p_outcome, 'deleted')
  assert.equal(calls.filter((call) => call.name === 'claim_trash_purge_storage_deletions').length, 2)
})

test('a failed Storage effect exits the batch loop for durable retry', async () => {
  const { client, calls } = clientFor({ status: 503 })
  assert.deepEqual(await runTrashPurgeBatch(client), [{ operationId: 'operation', code: 'retryable' }])
  assert.equal(calls.find((call) => call.name === 'finish_trash_purge_storage_deletion')?.args.p_outcome, 'failed')
  assert.equal(calls.filter((call) => call.name === 'claim_trash_purge_storage_deletions').length, 1)
})

test('only explicit Storage 404 variants are idempotent deletion success', () => {
  assert.equal(isExplicitStorageNotFound({ code: '404' }), true)
  assert.equal(isExplicitStorageNotFound({ status: 500 }), false)
  assert.equal(isExplicitStorageNotFound(null), false)
})
