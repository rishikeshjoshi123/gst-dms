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

test('signup validates normal account inputs before creating an auth user', () => {
  const schemaParse = signUpAction.indexOf('signupSchema.safeParse')
  const authSignup = signUpAction.indexOf('supabase.auth.signUp')

  assert.ok(schemaParse >= 0)
  assert.ok(authSignup > schemaParse)
  assert.match(authAction, /trim\(\)\.toLowerCase\(\)\.email\(\)\.max\(320\)/)
  assert.match(authAction, /password: z\.string\(\)\.min\(8\)\.max\(72\)/)
  assert.doesNotMatch(signUpAction, /INVITATION_INTENT_COOKIE|validate_organisation_invitation_signup/)
})

test('signup uses the ordinary verification callback and non-disclosing errors', () => {
  assert.match(signUpAction, /emailRedirectTo: new URL\('\/auth\/callback\?next=\/onboarding'/)
  assert.match(signUpAction, /The account could not be created\. Check the details and try again\./)
  assert.doesNotMatch(signUpAction, /error\.message/)
  assert.match(signupPage, /result\?\.success\) setSubmitted\(true\)/)
  assert.match(signupPage, /check your email for a verification link/i)
})

test('verification and invitation links land on explicit create-or-join onboarding', () => {
  assert.match(authCallback, /contexts\?\.some\(\(context\) => context\.state === 'active'\)/)
  assert.match(authCallback, /'\/dashboard' : '\/onboarding'/)
  assert.match(authCallback, /exchangeCodeForSession/)
  assert.match(authCallback, /cookieStore\.delete\('organisation_invitation_intent'\)/)
  assert.match(authCallback, /redirect\(contexts\?\.some/)
  assert.doesNotMatch(authCallback, /accept_organisation_invite|\/api\/invites\/accept' :/)
  assert.match(invitationRoute, /NextResponse\.redirect\(`\$\{origin\}\/signup`\)/)
  assert.match(invitationRoute, /NextResponse\.redirect\(`\$\{origin\}\/onboarding`\)/)
  assert.doesNotMatch(invitationRoute, /accept_organisation_invite/)
})
