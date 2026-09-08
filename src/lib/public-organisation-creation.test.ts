import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { isPublicOrganisationCreationEnabled } from './pilot-release-policy'

const organisationActions = readFileSync(new URL('./actions/org.ts', import.meta.url), 'utf8')
const createOrganisation = organisationActions.slice(
  organisationActions.indexOf('export async function createOrganisation'),
  organisationActions.indexOf('// ── Switch Organisation'),
)
const onboarding = readFileSync(new URL('../app/(auth)/onboarding/page.tsx', import.meta.url), 'utf8')

test('the pilot release disables public organisation creation', () => {
  assert.equal(isPublicOrganisationCreationEnabled(), false)
})

test('the server action contains no organisation creation path', () => {
  assert.match(createOrganisation, /A CaseChain invitation is required/)
  assert.doesNotMatch(createOrganisation, /createClient|create_organisation|redirect/)
})

test('onboarding exposes invitation entry without a create-workspace control', () => {
  assert.match(onboarding, /Invitation required/)
  assert.match(onboarding, /Accept invitation/)
  assert.doesNotMatch(onboarding, /createOrganisation|Create a new organisation|Create workspace/)
})
