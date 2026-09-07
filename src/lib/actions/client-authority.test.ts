import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const actionSource = readFileSync(new URL('./client.ts', import.meta.url), 'utf8')
const createButtonSource = readFileSync(
  new URL('../../app/(app)/clients/NewClientButton.tsx', import.meta.url),
  'utf8',
)

test('client create and update use authenticated command boundaries', () => {
  const mutationSource = actionSource.slice(actionSource.indexOf('export async function createClientAction'))
  assert.match(mutationSource, /supabase\.rpc\('create_client_command'/)
  assert.match(mutationSource, /supabase\.rpc\('update_client_command'/)
  assert.doesNotMatch(mutationSource, /createServiceClient/)
  assert.doesNotMatch(mutationSource, /\.from\('clients'\)\s*\.insert/)
  assert.doesNotMatch(mutationSource, /\.from\('clients'\)\s*\.update/)
})

test('the live create form preserves one idempotency key across a retry', () => {
  assert.match(createButtonSource, /useRef\(crypto\.randomUUID\(\)\)/)
  assert.match(createButtonSource, /formData\.set\('idempotencyKey', idempotencyKey\.current\)/)
  assert.match(createButtonSource, /idempotencyKey\.current = crypto\.randomUUID\(\)/)
})
