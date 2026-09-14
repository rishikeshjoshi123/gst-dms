import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const actions=readFileSync(new URL('./org.ts',import.meta.url),'utf8')
const email=readFileSync(new URL('../email.ts',import.meta.url),'utf8')
const migration=readFileSync(new URL('../../../supabase/migrations/00160_governed_team_invitation_administration.sql',import.meta.url),'utf8')

test('invitation actions use bounded normalized input and caller-retained retry keys',()=>{
  assert.match(actions,/emailSchema = z\.string\(\)\.trim\(\)\.toLowerCase\(\)\.email\(\)\.max\(320\)/)
  assert.match(actions,/formData\.get\('idempotency_key'\)/)
  assert.match(actions,/expectedRevision/)
  assert.match(actions,/revalidatePath\('\/team'\)/)
  assert.equal(actions.match(/deliveryRecordError/g)?.length,4)
  assert.equal(actions.match(/deliveryRecordCode/g)?.length,4)
  assert.match(actions,/delivery status could not be recorded/)
  assert.match(email,/if \(!captureTarget\) return \{ success: false, error: 'delivery_failed' \}/)
  assert.doesNotMatch(email,/local-capture-disabled/)
  assert.doesNotMatch(actions,/get_organisation_invites'\)/)
})

test('database commands derive exact active tenant and serialize rate decisions',()=>{
  assert.match(migration,/current_active_tenant_membership\(\)/g)
  assert.match(migration,/pg_advisory_xact_lock/g)
  assert.match(migration,/request_fingerprint/g)
  assert.match(migration,/pending_exists/)
  assert.match(migration,/count\(\*\)>=3/)
  assert.match(migration,/count\(\*\)>=50/)
  assert.match(migration,/membership\.state IN \('active','suspended'\)/)
  assert.match(migration,/coalesce\(v_reason,''\)/)
  assert.match(migration,/lifecycle_reason=v_reason/)
  assert.match(migration,/state='superseded',selector_hash=NULL/)
  assert.match(migration,/clock_timestamp\(\)\+interval '7 days'/)
  assert.match(migration,/REVOKE ALL ON public\.org_invites,public\.organisation_invites/)
  assert.doesNotMatch(migration,/selector_hash[^\n]+RETURNS TABLE/)
})
