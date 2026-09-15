import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

test('trusted placement orchestration is server-only and invokes only the typed service RPC', async () => {
  const source = await readFile(new URL('./placement-orchestration.ts', import.meta.url), 'utf8')
  assert.match(source, /import 'server-only'/)
  assert.match(source, /createServiceClient\(\)\.rpc\('produce_ambiguous_intake_placement_review'/)
  assert.doesNotMatch(source, /raw_provider_response|confidence|window|cookies|createClient\(/i)
})
