import assert from 'node:assert/strict'
import test from 'node:test'
import { formatInrDecimal } from './format-inr-decimal'
test('formats INR decimals without numeric precision loss', () => {
  assert.equal(formatInrDecimal('1200.50'), '₹1,200.50')
  assert.equal(formatInrDecimal('9007199254740991.99'), '₹9,00,71,99,25,47,40,991.99')
  assert.equal(formatInrDecimal('0.123456'), '₹0.123456')
})
