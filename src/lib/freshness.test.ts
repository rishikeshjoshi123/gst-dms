import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

import { freshnessLabel } from './freshness'

test('freshness labels describe authoritative fetch age without claiming live state', () => {
  assert.equal(freshnessLabel(1_000, 30_000, false), 'Refreshed just now')
  assert.equal(freshnessLabel(1_000, 181_000, false), 'Refreshed 3 min ago')
  assert.equal(freshnessLabel(1_000, 181_000, true), 'Offline · Refreshed 3 min ago')
  assert.equal(freshnessLabel(null, 181_000, false), 'Refresh unavailable')
})

test('the Hub fallback reconciles only while foregrounded and never claims Live', async () => {
  const source = await readFile(
    new URL('../app/(app)/documents/DocumentHubClientView.tsx', import.meta.url),
    'utf8',
  )

  assert.match(source, /55_000 \+ Math\.floor\(Math\.random\(\) \* 10_001\)/)
  assert.match(source, /document\.visibilityState === 'hidden'/)
  assert.match(source, /addEventListener\('focus', reconcileOnFocus\)/)
  assert.match(source, /addEventListener\('online', reconcileOnFocus\)/)
  assert.match(source, /addEventListener\('offline', reconcileOnFocus\)/)
  assert.doesNotMatch(source, />Live</)
})
