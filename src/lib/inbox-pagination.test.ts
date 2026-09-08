import assert from 'node:assert/strict'
import test from 'node:test'
import { readFile } from 'node:fs/promises'

import {
  INBOX_QUEUE_MAX_PAGE_SIZE,
  INBOX_QUEUE_PAGE_SIZE,
  normalizeInboxQueuePage,
} from './inbox-pagination'

test('uses a bounded first page by default', () => {
  assert.deepEqual(normalizeInboxQueuePage(), {
    offset: 0,
    limit: INBOX_QUEUE_PAGE_SIZE,
    includeId: undefined,
  })
})

test('normalizes invalid offsets and caps caller-controlled page sizes', () => {
  assert.deepEqual(normalizeInboxQueuePage({ offset: -4, limit: 10_000 }), {
    offset: 0,
    limit: INBOX_QUEUE_MAX_PAGE_SIZE,
    includeId: undefined,
  })
  assert.equal(normalizeInboxQueuePage({ offset: 25, limit: 25 }).offset, 25)
  assert.equal(normalizeInboxQueuePage({ offset: 25, limit: 25 }).limit, 25)
})

test('keeps only a non-empty explicitly requested selection id', () => {
  const selectedId = '0198f292-a8db-7def-8123-0123456789ab'
  assert.equal(normalizeInboxQueuePage({ includeId: ` ${selectedId} ` }).includeId, selectedId)
  assert.equal(normalizeInboxQueuePage({ includeId: '   ' }).includeId, undefined)
  assert.equal(normalizeInboxQueuePage({ includeId: 'not-a-uuid' }).includeId, undefined)
})

test('the canonical reader uses exact bounded pages and the Hub exposes truthful loading state', async () => {
  const [reader, hub] = await Promise.all([
    readFile(new URL('./actions/inbox.ts', import.meta.url), 'utf8'),
    readFile(new URL('../app/(app)/documents/DocumentHubClientView.tsx', import.meta.url), 'utf8'),
  ])

  assert.match(reader, /select\(INBOX_QUEUE_SELECT, \{ count: 'exact' \}\)/)
  assert.match(reader, /\.range\(offset, offset \+ limit - 1\)/)
  assert.match(reader, /select\('id', \{ count: 'exact', head: true \}\)/)
  assert.match(hub, /Load more documents/)
  assert.match(hub, /matches in.*loaded.*total/)
  assert.match(hub, /includeId: index === 0 \? selectedIdRef\.current/)
})
