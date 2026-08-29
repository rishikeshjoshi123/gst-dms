import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

test('renders timeline fallback metadata from typed document columns', () => {
  const source = readFileSync(new URL('./TimelineListFallback.tsx', import.meta.url), 'utf8')

  assert.doesNotMatch(source, /raw_metadata/)
  assert.match(source, /doc_date\?: string \| null/)
  assert.match(source, /reference_number\?: string \| null/)
  assert.match(source, /summary\?: string \| null/)
  assert.match(source, /financial_year\?: string \| null/)
  assert.match(source, /display_title\?: string \| null/)
  assert.match(source, /doc\.reference_number \|\| doc\.display_title \|\| doc\.storage_path/)
})
