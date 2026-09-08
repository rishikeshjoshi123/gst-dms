import assert from 'node:assert/strict'
import test from 'node:test'

import { getInitials } from './utils'

test('gets initials from Unicode graphemes in a multi-token display name', () => {
  assert.equal(getInitials('  A\u0301lvaro  N\u0303unez  '), 'A\u0301N\u0303')
  assert.equal(getInitials('नमस्ते कुमार'), 'नकु')
})

test('uses the first two graphemes for a single name token', () => {
  assert.equal(getInitials('Åsa'), 'ÅS')
  assert.equal(getInitials('👩🏽‍💼Casey'), '👩🏽‍💼C')
})

test('does not manufacture initials without a usable display name', () => {
  assert.equal(getInitials(undefined), null)
  assert.equal(getInitials('   '), null)
})
