import assert from 'node:assert/strict'
import test from 'node:test'
import { readFileSync } from 'node:fs'

import { enqueueTrashPurgeSweepPage, isExplicitStorageNotFound, nextTrashPurgeFailureWake, runTrashPurgeBatch, runTrashPurgeDispatchCycle, type TrashPurgeDispatchPayload, type TrashPurgeRpcClient } from './purge-worker'

function clientFor(removeError: unknown = null) {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  let deletionClaim = 0
  const client: TrashPurgeRpcClient = {
    async rpc(name, args) {
      calls.push({ name, args })
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

test('a thrown Storage transport error is durably recorded as failed', async () => {
  const { client, calls } = clientFor({ status: 503 })
  client.storage = { from: () => ({ async remove() { throw new Error('connection reset') } }) }
  assert.deepEqual(await runTrashPurgeBatch(client), [{ operationId: 'operation', code: 'retryable' }])
  assert.equal(calls.find((call) => call.name === 'finish_trash_purge_storage_deletion')?.args.p_outcome, 'failed')
})

test('only explicit Storage 404 variants are idempotent deletion success', () => {
  assert.equal(isExplicitStorageNotFound({ code: '404' }), true)
  assert.equal(isExplicitStorageNotFound({ status: 500 }), false)
  assert.equal(isExplicitStorageNotFound(null), false)
})

test('daily sweep advances past a full page using database-issued keyset cursor', async () => {
  const calls: Record<string, unknown>[] = []
  const client = {
    async rpc(name: string, args: Record<string, unknown>) {
      assert.equal(name, 'enqueue_due_trash_purges_page')
      calls.push(args)
      return { data: [{ examined_count: calls.length === 1 ? 100 : 2,
        queued_count: 2, last_at: '2026-09-15T00:00:00+00:00', last_id: '00000000-0000-0000-0000-000000000001' }], error: null }
    },
    storage: { from: () => ({ async remove() { return { data: null, error: null } } }) },
  } satisfies TrashPurgeRpcClient
  const first = await enqueueTrashPurgeSweepPage(client, null)
  assert.equal(first.examined, 100)
  assert.ok(first.next)
  const second = await enqueueTrashPurgeSweepPage(client, first.next)
  assert.equal(second.next, null)
  assert.equal(calls[1].p_after_id, first.next?.id)
})

test('failure wake is supplied only by durable database retry/lease clock', async () => {
  const client = {
    async rpc(name: string) {
      assert.equal(name, 'next_trash_purge_failure_wake')
      return { data: [{ wake_at: '2026-09-15T00:00:30+00:00' }], error: null }
    },
    storage: { from: () => ({ async remove() { return { data: null, error: null } } }) },
  } satisfies TrashPurgeRpcClient
  assert.equal((await nextTrashPurgeFailureWake(client))?.toISOString(), '2026-09-15T00:00:30.000Z')
})

test('Trigger registers only midnight-IST routine purge and no pilot Team projector', () => {
  const source = readFileSync(new URL('../../trigger/outbox.ts', import.meta.url), 'utf8')
  assert.match(source, /id: 'sweep-trash-permanent-delete-daily',[\s\S]*?pattern: '0 0 \* \* \*', timezone: 'Asia\/Kolkata'/)
  assert.doesNotMatch(source, /id: 'reconcile-trash-permanent-delete'/)
  assert.doesNotMatch(source, /id: 'project-trash-retention-team-attention'/)
  assert.match(source, /delay: new Date\(Math\.max\(wakeAt\.getTime\(\), Date\.now\(\) \+ 2000\)\)/)
})

test('the registered India midnight is the prior UTC day at 18:30, independent of traveller locale', () => {
  const instant = new Date('2026-09-14T18:30:00.000Z')
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).format(instant)
  assert.equal(parts, '15/09/2026, 00:00')
})

test('daily dispatcher continues a bounded full-page sweep from its last keyset cursor', async () => {
  let pages = 0
  const continued: TrashPurgeDispatchPayload[] = []
  const client = {
    async rpc(name: string) {
      if (name === 'enqueue_due_trash_purges_page') {
        pages += 1
        return { data: [{ examined_count: pages <= 20 ? 100 : 0, queued_count: 0,
          last_at: '2026-09-15T00:00:00+00:00', last_id: `00000000-0000-0000-0000-${String(pages).padStart(12, '0')}` }], error: null }
      }
      if (name === 'claim_trash_purge_work') return { data: [], error: null }
      if (name === 'next_trash_purge_failure_wake') return { data: [{ wake_at: null }], error: null }
      throw new Error(`unexpected RPC ${name}`)
    },
    storage: { from: () => ({ async remove() { return { data: null, error: null } } }) },
  } satisfies TrashPurgeRpcClient
  const wakes = { continue: async (payload: TrashPurgeDispatchPayload) => { continued.push(payload) },
    failure: async () => { throw new Error('no failure expected') } }
  const first = await runTrashPurgeDispatchCycle(client, { routine: true }, wakes)
  assert.equal(first.continuation, true)
  assert.equal(pages, 20)
  assert.equal(continued.length, 1)
  assert.equal(continued[0].cursor?.id, '00000000-0000-0000-0000-000000000020')
  const second = await runTrashPurgeDispatchCycle(client, continued[0], wakes)
  assert.equal(second.continuation, false)
  assert.equal(pages, 21)
  assert.equal(continued.length, 1)
})

test('duplicate empty daily wakes are inert and a failed-job clock alone creates delayed wake', async () => {
  let wakeAt: string | null = null
  let pageCalls = 0
  const delayed: string[] = []
  const client = {
    async rpc(name: string) {
      if (name === 'enqueue_due_trash_purges_page') {
        pageCalls += 1
        return { data: [{ examined_count: 0, queued_count: 0 }], error: null }
      }
      if (name === 'claim_trash_purge_work') return { data: [], error: null }
      if (name === 'next_trash_purge_failure_wake') return { data: [{ wake_at: wakeAt }], error: null }
      throw new Error(`unexpected RPC ${name}`)
    },
    storage: { from: () => ({ async remove() { return { data: null, error: null } } }) },
  } satisfies TrashPurgeRpcClient
  const wakes = { continue: async () => { throw new Error('no continuation expected') },
    failure: async (at: Date) => { delayed.push(at.toISOString()) } }
  await runTrashPurgeDispatchCycle(client, { routine: true }, wakes)
  await runTrashPurgeDispatchCycle(client, { routine: true }, wakes)
  assert.equal(pageCalls, 2)
  assert.deepEqual(delayed, [])
  wakeAt = '2026-09-15T00:00:30+00:00'
  await runTrashPurgeDispatchCycle(client, {}, wakes)
  assert.equal(pageCalls, 2)
  assert.deepEqual(delayed, ['2026-09-15T00:00:30.000Z'])
})
