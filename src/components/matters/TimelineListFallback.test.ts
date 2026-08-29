import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { compareTimelineDocuments, timelineSortTimestamp } from './TimelineListFallback'

test('renders timeline fallback without raw metadata fallback', () => {
  const source = readFileSync(new URL('./TimelineListFallback.tsx', import.meta.url), 'utf8')

  assert.doesNotMatch(source, /raw_metadata/)
  assert.match(source, /doc_date\?: string \| null/)
  assert.match(source, /reference_number\?: string \| null/)
  assert.match(source, /summary\?: string \| null/)
  assert.match(source, /financial_year\?: string \| null/)
  assert.match(source, /display_title\?: string \| null/)
  assert.match(source, /effective\.referenceNumber/)
})

test('sorts by corrected effective date and uses created_at when date is unavailable', () => {
  const document = { id: 'document-a', created_at: '2026-01-02T00:00:00.000Z' }
  assert.equal(timelineSortTimestamp(document, { state: 'available', documentDate: '2026-08-30' }), new Date('2026-08-30T00:00:00').getTime())
  assert.equal(timelineSortTimestamp(document, { state: 'available', documentDate: null }), new Date(document.created_at).getTime())
  assert.equal(timelineSortTimestamp(document, { state: 'unavailable', documentDate: '2099-01-01' }), new Date(document.created_at).getTime())
})

test('sorts ascending by effective chronology, then creation time and ID', () => {
  const rows = [
    { id: 'c', created_at: '2026-01-03T00:00:00.000Z' },
    { id: 'b', created_at: '2026-01-02T00:00:00.000Z' },
    { id: 'a', created_at: '2026-01-02T00:00:00.000Z' },
    { id: 'corrected', created_at: '2026-01-05T00:00:00.000Z' },
  ]
  const metadata = {
    c: { state: 'unavailable' as const, documentDate: null },
    b: { state: 'unavailable' as const, documentDate: null },
    a: { state: 'unavailable' as const, documentDate: null },
    corrected: { state: 'available' as const, documentDate: '2025-12-31' },
  }

  assert.deepEqual(
    rows.sort((a, b) => compareTimelineDocuments(a, b, metadata)).map(({ id }) => id),
    ['corrected', 'a', 'b', 'c'],
  )
})
