import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { isReprocessScope, reprocessScopes } from './reprocess'

test('accepts exactly the approved explicit reprocess scopes', () => {
  assert.deepEqual(reprocessScopes, ['extract', 'ocr', 'relationships', 'search_index', 'full'])
  for (const scope of reprocessScopes) assert.equal(isReprocessScope(scope), true)
  for (const scope of ['validate', 'all', '', null, { scope: 'full' }]) assert.equal(isReprocessScope(scope), false)
})

test('does not expose queued reprocessing before a scoped worker is deployed', () => {
  const source = readFileSync(new URL('./reprocess.ts', import.meta.url), 'utf8')

  assert.match(source, /Scoped reprocessing is unavailable until its dedicated worker is deployed\./)
  assert.doesNotMatch(source, /request_document_reprocess/)
  assert.doesNotMatch(source, /scheduleDocumentOutboxWake/)
  assert.doesNotMatch(source, /\sas any\b/)
  assert.doesNotMatch(source, /@trigger\.dev\/sdk|\.trigger\(/)
  assert.doesNotMatch(source, /(storagePath|object_key|signed_url|raw_metadata)/)
})

test('keeps legacy Inbox rows away from the canonical reprocess command', () => {
  const inboxSource = readFileSync(new URL('../../app/(app)/inbox/InboxClientView.tsx', import.meta.url), 'utf8')

  assert.doesNotMatch(inboxSource, /reprocessDocument/)
  assert.doesNotMatch(inboxSource, /handleReprocess/)
})

test('uses visible, touch-target shared actions in the Timeline document header', () => {
  const timelineSource = readFileSync(new URL('../../components/matters/TimelineDocumentDetail.tsx', import.meta.url), 'utf8')

  assert.match(timelineSource, /<Button[\s\S]*?disabled[\s\S]*?>[\s\S]*?Reprocess unavailable/)
  assert.match(timelineSource, /<Button[\s\S]*?onClick=\{\(\) => setIsDocConfirmOpen\(true\)\}[\s\S]*?>[\s\S]*?Delete document/)
  assert.doesNotMatch(timelineSource, /size="icon"[\s\S]{0,200}Delete Document/)
})

test('keeps failed timeline status copy aligned with unavailable scoped reprocessing', () => {
  const graphSource = readFileSync(new URL('../../components/matters/TimelineGraphNode.tsx', import.meta.url), 'utf8')

  assert.match(graphSource, /manual recovery is required while scoped reprocessing is unavailable/)
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
