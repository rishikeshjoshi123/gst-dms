import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const authAction = readFileSync(new URL('./auth.ts', import.meta.url), 'utf8')
const signUpAction = authAction.slice(
  authAction.indexOf('export async function signUp'),
  authAction.indexOf('export type SignInState'),
)
const invitationRoute = readFileSync(
  new URL('../../app/api/invites/accept/route.ts', import.meta.url),
  'utf8',
)
const authCallback = readFileSync(
  new URL('../../app/auth/callback/route.ts', import.meta.url),
  'utf8',
)
const signupPage = readFileSync(
  new URL('../../app/(auth)/signup/page.tsx', import.meta.url),
  'utf8',
)

test('signup requires an invitation intent before creating an auth user', () => {
  const cookieCheck = signUpAction.indexOf('cookieStore.get(INVITATION_INTENT_COOKIE)')
  const invitationDenial = signUpAction.indexOf('A valid organisation invitation is required')
  const authSignup = signUpAction.indexOf('supabase.auth.signUp')

  assert.ok(cookieCheck >= 0)
  assert.ok(invitationDenial > cookieCheck)
  assert.ok(authSignup > invitationDenial)
})

test('signup validates the invitation and email before creating an auth user', () => {
  const eligibilityCheck = signUpAction.indexOf("supabase.rpc('validate_organisation_invitation_signup'")
  const eligibilityDenial = signUpAction.indexOf("eligibility !== 'eligible'")
  const authSignup = signUpAction.indexOf('supabase.auth.signUp')

  assert.ok(eligibilityCheck >= 0)
  assert.ok(eligibilityDenial > eligibilityCheck)
  assert.ok(authSignup > eligibilityDenial)
  assert.match(signUpAction, /trim\(\)\.toLowerCase\(\)/)
  assert.match(authAction, /createHash\('sha256'\)/)
})

test('new invitees enter through signup and finish after email verification', () => {
  assert.match(invitationRoute, /NextResponse\.redirect\(`\$\{origin\}\/signup`\)/)
  assert.match(authCallback, /intent \? '\/api\/invites\/accept' : next/)
  assert.match(signupPage, /result\?\.success\) setSubmitted\(true\)/)
  assert.match(signupPage, /Check your email to verify the account/)
})
