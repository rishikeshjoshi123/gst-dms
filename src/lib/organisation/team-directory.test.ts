import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(new URL('./team-directory.ts', import.meta.url), 'utf8')
const migration = readFileSync(new URL('../../../supabase/migrations/00139_team_directory_page.sql', import.meta.url), 'utf8')

test('Team reader is typed, bounded, allowlisted, and distinguishes metadata outcomes', () => {
  assert.match(source, /supabase\.rpc\('get_team_directory'/)
  assert.match(source, /Math\.min\(params\.limit!, MAX_LIMIT\)/)
  assert.match(source, /error: 'unavailable'/)
  assert.match(source, /row\.outcome_code === 'ok'/)
  assert.match(source, /params\.role === 'admin'/)
  assert.match(source, /params\.state === 'active'/)
  assert.match(source, /offset: meta\.page_offset/)
  assert.match(source, /meta\.outcome_code !== 'ok'/)
  assert.doesNotMatch(source, /as any/)
})

test('Team RPC has a text signature, sentinel outcomes, and literal LIKE escaping', () => {
  assert.match(migration, /get_team_directory\(p_query text DEFAULT NULL,p_role text DEFAULT NULL,p_state text DEFAULT NULL,p_limit integer DEFAULT 50,p_offset integer DEFAULT 0\)/)
  assert.match(migration, /chr\(92\)/)
  assert.match(migration, /ESCAPE E'\\\\'/)
  assert.match(migration, /eligible_count<>1/)
  assert.match(migration, /'unavailable'/)
})
