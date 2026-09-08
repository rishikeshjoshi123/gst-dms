import assert from 'node:assert/strict'
import test from 'node:test'

import type { InboxQueueDocument } from './actions/inbox'
import { reconcileInboxQueue } from './inbox-queue-read'
import { readFile } from 'node:fs/promises'

const existing = [{ id: 'existing' }] as InboxQueueDocument[]

test('a successful empty queue clears the last snapshot', () => {
  const result = reconcileInboxQueue(existing, { ok: true, documents: [], total: 0, offset: 0, limit: 50 })
  assert.deepEqual(result, { documents: [], error: null })
})

test('a genuine read failure preserves the last successful snapshot', () => {
  const result = reconcileInboxQueue(existing, { ok: false, error: 'Read failed.' })
  assert.deepEqual(result.documents, existing)
  assert.match(result.error ?? '', /Read failed.*last loaded documents/)
})

test('the Hub fences signed source results by selected subject and generation', async () => {
  const source = await readFile(
    new URL('../app/(app)/documents/DocumentHubClientView.tsx', import.meta.url),
    'utf8',
  )

  assert.match(source, /sourceRequestGeneration\.current !== generation/)
  assert.match(source, /selectedIdRef\.current !== subjectId/)
  assert.match(source, /sourceRequestGeneration\.current \+= 1/)
})
