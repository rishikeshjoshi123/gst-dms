import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { isReprocessIdempotencyKey, isReprocessScope, reprocessScopes } from './reprocess'

test('accepts exactly the approved explicit reprocess scopes', () => {
  assert.deepEqual(reprocessScopes, ['extract', 'ocr', 'relationships', 'search_index', 'full'])
  for (const scope of reprocessScopes) assert.equal(isReprocessScope(scope), true)
  for (const scope of ['validate', 'all', '', null, { scope: 'full' }]) assert.equal(isReprocessScope(scope), false)
})

test('exposes only the proven search-index reprocess command through the durable wake', () => {
  const source = readFileSync(new URL('./reprocess.ts', import.meta.url), 'utf8')

  assert.match(source, /Other scopes are unavailable until their dedicated workers are deployed/)
  assert.match(source, /request_document_reprocess/)
  assert.match(source, /scheduleDocumentOutboxWake/)
  assert.match(source, /scope !== 'search_index'/)
  assert.doesNotMatch(source, /\sas any\b/)
  assert.doesNotMatch(source, /@trigger\.dev\/sdk|\.trigger\(/)
  assert.doesNotMatch(source, /(storagePath|object_key|signed_url|raw_metadata)/)
})

test('requires a caller-owned UUID idempotency key for a retriable command', () => {
  assert.equal(isReprocessIdempotencyKey('54800000-0000-0000-0000-000000000006'), true)
  assert.equal(isReprocessIdempotencyKey('retry-me'), false)
  assert.equal(isReprocessIdempotencyKey(undefined), false)
})

test('keeps legacy Inbox rows away from the canonical reprocess command', () => {
  const inboxSource = readFileSync(new URL('../../app/(app)/inbox/InboxClientView.tsx', import.meta.url), 'utf8')

  assert.doesNotMatch(inboxSource, /reprocessDocument/)
  assert.doesNotMatch(inboxSource, /handleReprocess/)
})

test('uses visible, touch-target shared actions and truthful scoped-reprocess status in the Timeline document header', () => {
  const timelineSource = readFileSync(new URL('../../components/matters/TimelineDocumentDetail.tsx', import.meta.url), 'utf8')

  assert.match(timelineSource, /reprocessDocument\(doc.id, 'search_index', reprocessIdempotencyKey.current\)/)
  assert.match(timelineSource, /crypto.randomUUID\(\)/)
  assert.match(timelineSource, /Reprocess search index/)
  assert.match(timelineSource, /Search-index reprocessing is available\. Extraction, OCR, relationship, and full reprocessing remain unavailable/)
  assert.match(timelineSource, /<Button[\s\S]*?onClick=\{\(\) => setIsDocConfirmOpen\(true\)\}[\s\S]*?>[\s\S]*?Delete document/)
  assert.doesNotMatch(timelineSource, /size="icon"[\s\S]{0,200}Delete Document/)
})

test('keeps failed timeline status copy aligned with the available index-only scope', () => {
  const graphSource = readFileSync(new URL('../../components/matters/TimelineGraphNode.tsx', import.meta.url), 'utf8')

  assert.match(graphSource, /Search-index reprocessing may be available; other scopes require manual recovery/)
  assert.doesNotMatch(graphSource, /use Reprocess to retry/)
})

test('serializes an actor reprocess key before inspecting its receipt', () => {
  const migrationSource = readFileSync(
    new URL('../../../supabase/migrations/00054_scoped_durable_document_reprocess.sql', import.meta.url),
    'utf8',
  )
  const lockIndex = migrationSource.indexOf('pg_advisory_xact_lock')
  const receiptLookupIndex = migrationSource.indexOf('SELECT * INTO prior FROM public.document_command_receipts')

  assert.ok(lockIndex >= 0)
  assert.ok(receiptLookupIndex > lockIndex)
  assert.match(migrationSource, /actor_id::text\|\|':reprocess:'\|\|p_idempotency::text/)
})
