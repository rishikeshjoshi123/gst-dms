import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(new URL('./notes.ts', import.meta.url), 'utf8')
const removal = source.slice(source.indexOf('export async function deleteNote'))

test('note removal uses the authenticated command boundary', () => {
  assert.match(removal, /supabase\.rpc\('remove_case_note'/)
  assert.doesNotMatch(removal, /createServiceClient/)
  assert.doesNotMatch(removal, /\.update\(\{\s*deleted_at:/)
})

test('note removal handles command denials and revalidates returned context', () => {
  assert.match(removal, /reason_required:/)
  assert.match(removal, /not_allowed:/)
  assert.match(removal, /result\.matter_id/)
  assert.match(removal, /result\.document_id/)
  assert.match(removal, /already_removed/)
})
