import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const actionSource = readFileSync(new URL('./matter.ts', import.meta.url), 'utf8')
const createButtonSource = readFileSync(
  new URL('../../app/(app)/clients/[id]/NewMatterButton.tsx', import.meta.url),
  'utf8',
)
const detailsSource = readFileSync(
  new URL('../../components/matters/MatterDetailsTab.tsx', import.meta.url),
  'utf8',
)

test('matter create and update use authenticated command boundaries', () => {
  const mutationSource = actionSource.slice(actionSource.indexOf('export async function createMatter'))
  assert.match(mutationSource, /supabase\.rpc\('create_matter_command'/)
  assert.match(mutationSource, /supabase\.rpc\('update_matter_command'/)
  assert.doesNotMatch(mutationSource, /createServiceClient/)
  assert.doesNotMatch(mutationSource, /\.from\('matters'\)\s*\.insert/)
  assert.doesNotMatch(mutationSource, /\.from\('matters'\)\s*\.update/)
})

test('live matter forms preserve one idempotency key across a retry', () => {
  assert.match(createButtonSource, /useRef\(crypto\.randomUUID\(\)\)/)
  assert.match(createButtonSource, /formData\.set\('idempotencyKey', idempotencyKey\.current\)/)
  assert.match(createButtonSource, /idempotencyKey\.current = crypto\.randomUUID\(\)/)
  assert.match(detailsSource, /matterUpdateIdempotencyKey\.current = crypto\.randomUUID\(\)/)
  assert.match(detailsSource, /expectedRevision: matter\.revision/)
  assert.match(detailsSource, /idempotencyKey: matterUpdateIdempotencyKey\.current/)
})
