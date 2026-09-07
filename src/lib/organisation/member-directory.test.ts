import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const files = [
  new URL('./member-directory.ts', import.meta.url),
  new URL('../actions/notes.ts', import.meta.url),
  new URL('../actions/notifications.ts', import.meta.url),
  new URL('../../app/(app)/notes/page.tsx', import.meta.url),
  new URL('../../app/(app)/matters/[id]/page.tsx', import.meta.url),
]
const sources = files.map((file) => readFileSync(file, 'utf8'))

test('Notes, Matter, and Activity contain no global Auth-admin directory lookup', () => {
  for (const source of sources) {
    assert.doesNotMatch(source, /auth\.admin\.listUsers|createServiceClient/)
  }
})

test('the shared directory maps the canonical user locator and filters assignees', () => {
  const source = sources[0]
  assert.match(source, /rpc\('get_my_team_members'\)/)
  assert.match(source, /id: member\.user_id/)
  assert.match(source, /member\.state === 'active'/)
  assert.match(source, /member\.role !== 'viewer'/)
})
