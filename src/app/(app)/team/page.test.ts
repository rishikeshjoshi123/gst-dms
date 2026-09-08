import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

test('Team page normalizes URL input before reading and rendering', () => {
  const source = readFileSync(new URL('./page.tsx', import.meta.url), 'utf8')
  assert.match(source, /normalizeTeamDirectoryParams\(query\)/)
  assert.match(source, /getTeamDirectory\(normalizedQuery\)/)
  assert.doesNotMatch(source, /as TeamDirectoryParams/)
})
