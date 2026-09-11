import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { isPublicOrganisationCreationEnabled } from './pilot-release-policy'

const organisationActions = readFileSync(new URL('./actions/org.ts', import.meta.url), 'utf8')
const createOrganisation = organisationActions.slice(
  organisationActions.indexOf('export async function createOrganisation'),
  organisationActions.indexOf('// ── Switch Organisation'),
)
const onboardingPage = readFileSync(new URL('../app/(auth)/onboarding/page.tsx', import.meta.url), 'utf8')
const onboardingClient = readFileSync(new URL('../app/(auth)/onboarding/OnboardingClient.tsx', import.meta.url), 'utf8')
const migration = readFileSync(
  new URL('../../supabase/migrations/00145_normal_create_or_join_onboarding.sql', import.meta.url),
  'utf8',
)

test('the pilot release enables verified-email organisation creation', () => {
  assert.equal(isPublicOrganisationCreationEnabled(), true)
})

test('the server action delegates organisation creation to the authenticated command', () => {
  assert.match(createOrganisation, /createClient/)
  assert.match(createOrganisation, /\.rpc\('create_organisation'/)
  assert.match(createOrganisation, /formData\.get\('idempotency_key'\)/)
  assert.match(createOrganisation, /z\.string\(\)\.uuid\(\)\.safeParse\(idempotencyKey\)/)
  assert.match(createOrganisation, /p_idempotency_key: idempotencyKey/)
  assert.doesNotMatch(createOrganisation, /p_idempotency_key: randomUUID\(\)/)
  assert.match(createOrganisation, /setCurrentOrg\(result\.org_id\)/)
  assert.match(createOrganisation, /redirect\('\/dashboard'\)/)
  assert.doesNotMatch(createOrganisation, /service_role|SUPABASE_SERVICE_ROLE_KEY/)
})

test('onboarding keeps invitations prominent and offers a distinct create action', () => {
  assert.match(onboardingPage, /get_my_pending_organisation_invites/)
  assert.match(onboardingPage, /current\?\.state === 'suspended'/)
  assert.match(onboardingClient, /Pending invitations/)
  assert.match(onboardingClient, /No pending invitations/)
  assert.match(onboardingClient, /Create organisation/)
  assert.match(onboardingClient, /<span>Log out<\/span>/)
  assert.doesNotMatch(onboardingClient, /hidden sm:inline">Log out/)
  assert.match(onboardingClient, /if \(input && !input\.value\) input\.value = crypto\.randomUUID\(\)/)
  assert.match(onboardingClient, /ref=\{setCreationIdempotencyKey\} type="hidden" name="idempotency_key"/)
  assert.match(onboardingClient, /acceptInvite/)
  assert.match(onboardingClient, /createOrganisation/)
})

test('the database command verifies identity and serializes against invite acceptance', () => {
  assert.match(migration, /email_confirmed_at IS NOT NULL/)
  assert.match(migration, /pg_advisory_xact_lock/)
  assert.match(migration, /hashtextextended\(v_actor::text,801\)/)
  assert.match(migration, /membership\.state IN \('active','suspended'\)/)
  assert.match(migration, /organisation_creation_command_receipts/)
  assert.match(migration, /organisation_creation\.completed\.v1/)
  assert.match(migration, /append_activity_event/)
  assert.match(migration, /activity_projector_outbox_events|organisation\.created/)
})
