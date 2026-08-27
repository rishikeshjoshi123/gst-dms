import assert from 'node:assert/strict'
import test from 'node:test'
import { createInvitationSelector, hashInvitationOpaqueValue, safeInternalRedirect } from './invitations'

test('invitation opaque values use stable SHA-256 hex hashes', () => {
  assert.equal(hashInvitationOpaqueValue('selector'), 'c7567ce69f1b1b776aee60bdf06af3daebbec1142da282672f3be93515a993f8')
  assert.match(hashInvitationOpaqueValue(createInvitationSelector()), /^[0-9a-f]{64}$/)
})

test('invitation redirects stay on this origin', () => {
  assert.equal(safeInternalRedirect('/api/invites/accept'), '/api/invites/accept')
  assert.equal(safeInternalRedirect('//attacker.test'), '/dashboard')
  assert.equal(safeInternalRedirect('https://attacker.test'), '/dashboard')
})
