import assert from 'node:assert/strict'
import test from 'node:test'
import { validateCallbackLocation, validateVerificationUrl } from './release-journey-boundary.mjs'

const contract={authOrigin:'http://127.0.0.1:56221',appOrigin:'http://127.0.0.1:3113'}
const verification='http://127.0.0.1:56221/auth/v1/verify?token=opaque-local-token&type=signup&redirect_to=http%3A%2F%2F127.0.0.1%3A3113%2Fauth%2Fcallback%3Fnext%3D%2Fonboarding'

test('accepts only the exact local signup verification and callback contract',()=>{
 assert.equal(validateVerificationUrl(verification,contract),verification)
 assert.equal(validateCallbackLocation('http://127.0.0.1:3113/auth/callback?code=opaque-code&next=%2Fonboarding',contract),'http://127.0.0.1:3113/auth/callback?code=opaque-code&next=%2Fonboarding')
})

test('rejects arbitrary verification and callback destinations before navigation',()=>{
 for(const candidate of [
  verification.replace('127.0.0.1:56221','example.test'),
  verification.replace('/auth/v1/verify','/auth/v1/token'),
  verification.replace('type=signup','type=recovery'),
  `${verification}&unexpected=true`,
  verification.replace('127.0.0.1%3A3113','example.test'),
 ]) assert.throws(()=>validateVerificationUrl(candidate,contract))
 for(const candidate of [
  'https://example.test/auth/callback?code=opaque-code&next=%2Fonboarding',
  '/other?code=opaque-code&next=%2Fonboarding',
  '/auth/callback?next=%2Fonboarding',
  '/auth/callback?code=opaque-code&next=%2Fdashboard',
 ]) assert.throws(()=>validateCallbackLocation(candidate,contract))
})

test('rejects hashes, duplicate fields, and embedded callback query pollution',()=>{
 for(const candidate of [
  `${verification}#fragment`,
  `${verification}&token=second`,
  `${verification}&type=signup`,
  `${verification}&redirect_to=http%3A%2F%2F127.0.0.1%3A3113%2Fauth%2Fcallback`,
  verification.replace('%2Fonboarding','%2Fonboarding%26next%3D%2Fonboarding'),
  verification.replace('%2Fonboarding','%2Fonboarding%26extra%3D1'),
  verification.replace('%2Fonboarding','%2Fonboarding%23fragment'),
 ]) assert.throws(()=>validateVerificationUrl(candidate,contract))
 for(const candidate of [
  '/auth/callback?code=opaque-code&next=%2Fonboarding#fragment',
  '/auth/callback?code=opaque-code&next=%2Fonboarding&code=second',
  '/auth/callback?code=opaque-code&next=%2Fonboarding&next=%2Fonboarding',
  '/auth/callback?code=opaque-code&next=%2Fonboarding&extra=1',
 ]) assert.throws(()=>validateCallbackLocation(candidate,contract))
})
