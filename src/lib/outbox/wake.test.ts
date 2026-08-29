import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import {
  documentOutboxWakeOptions,
  documentOutboxWakePayload,
  scheduleDocumentOutboxWake,
  submitDocumentOutboxWake,
} from './wake'

test('submits one fixed, content-free singleton dispatcher wake', async () => {
  const calls: Array<{ payload: unknown; options: unknown }> = []
  const result = await submitDocumentOutboxWake(async (payload, options) => {
    calls.push({ payload, options })
  })

  assert.deepEqual(result, { accepted: true })
  assert.deepEqual(calls, [{ payload: {}, options: documentOutboxWakeOptions }])
  assert.deepEqual(documentOutboxWakePayload, {})
  assert.deepEqual(documentOutboxWakeOptions, {
    debounce: { key: 'document-outbox-dispatch', delay: '5s', maxDelay: '30s' },
  })
})

test('a rejected wake is content-safe and cannot fail the durable command', async () => {
  const logs: string[] = []
  const result = await submitDocumentOutboxWake(
    async () => { throw new Error('signed URL and document content must not escape') },
    message => logs.push(message),
  )

  assert.deepEqual(result, { accepted: false })
  assert.deepEqual(logs, ['Document outbox wake was not accepted; scheduled recovery will drain durable work.'])
})

test('schedules the wake after the caller has completed its durable work', async () => {
  let callback: (() => void | Promise<void>) | undefined
  const calls: unknown[] = []
  scheduleDocumentOutboxWake(
    scheduled => { callback = scheduled },
    async payload => { calls.push(payload) },
  )

  assert.equal(calls.length, 0)
  await callback?.()
  assert.deepEqual(calls, [{}])
})

test('document actions and legacy workers cannot bypass the outbox with direct processing tasks', () => {
  const actionSources = [
    '../actions/document.ts',
    '../actions/reprocess.ts',
    '../actions/inbox.ts',
  ]
  for (const source of [
    ...actionSources,
    '../../trigger/jobs.ts',
    '../../../trigger_reprocess.ts',
  ]) {
    const file = readFileSync(new URL(source, import.meta.url), 'utf8')
    assert.doesNotMatch(file, /tasks\.trigger\(\s*['"](?:process-document|analyze-staged-document)['"]/)
  }
  for (const source of actionSources) {
    const file = readFileSync(new URL(source, import.meta.url), 'utf8')
    assert.doesNotMatch(file, /from ['"]@trigger\.dev\/sdk(?:\/v3)?['"]/)
  }
})

test('canonical upload and placement commands schedule only the fixed outbox wake after success', () => {
  const documentAction = readFileSync(new URL('../actions/document.ts', import.meta.url), 'utf8')
  const inboxAction = readFileSync(new URL('../actions/inbox.ts', import.meta.url), 'utf8')

  assert.match(documentAction, /complete_document_upload[\s\S]*?scheduleDocumentOutboxWake\(\)/)
  assert.match(inboxAction, /assign_intake_to_new_document[\s\S]*?scheduleDocumentOutboxWake\(\)/)
})

test('document processing derives child tenant identity from the database claim', () => {
  const worker = readFileSync(new URL('../../trigger/outbox.ts', import.meta.url), 'utf8')

  assert.match(worker, /claim_document_processing_work_for_dispatch/)
  assert.match(worker, /p_expected_org_id:\s*payload\.orgId/)
  assert.match(worker, /const claimOrgId = String\(claim\.org_id\)/)
  assert.match(worker, /orgId:\s*claimOrgId/)
  assert.match(worker, /concurrencyKey:\s*claimOrgId/)
  assert.doesNotMatch(worker, /concurrencyKey:\s*payload\.orgId/)
})

test('scoped reprocess passes the exact delivery lease token into its fenced claim', () => {
  const worker = readFileSync(new URL('../../trigger/outbox.ts', import.meta.url), 'utf8')

  assert.match(worker, /claim_document_search_index_reprocess_work[\s\S]*?p_event_id:\s*payload\.eventId,[\s\S]*?p_trigger_run_id:\s*ctx\.run\.id,[\s\S]*?p_expected_org_id:\s*payload\.orgId,[\s\S]*?p_delivery_lease_token:\s*payload\.leaseToken/)
})

test('a legacy unavailable scoped event is terminalized through its delivery fence', () => {
  const worker = readFileSync(new URL('../../trigger/outbox.ts', import.meta.url), 'utf8')

  assert.match(worker, /payload\.payload\.scope !== 'search_index'[\s\S]*?recover_unavailable_document_reprocess_event[\s\S]*?p_event_id:\s*payload\.eventId,[\s\S]*?p_expected_org_id:\s*payload\.orgId,[\s\S]*?p_delivery_lease_token:\s*payload\.leaseToken/)
  assert.doesNotMatch(worker, /queued_unavailable_scope/)
})
