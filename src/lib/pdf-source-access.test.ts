import assert from 'node:assert/strict'
import test from 'node:test'

import { pdfSourceLookupFailureCode } from './pdf-source-access'

test('distinguishes a temporary lookup failure from a proven unavailable source', () => {
  assert.equal(pdfSourceLookupFailureCode({ lookupFailed: true, sourceAvailable: false }), 'access_temporary')
  assert.equal(pdfSourceLookupFailureCode({ lookupFailed: false, sourceAvailable: false }), 'source_unavailable')
  assert.equal(pdfSourceLookupFailureCode({ lookupFailed: false, sourceAvailable: true }), null)
  assert.equal(pdfSourceLookupFailureCode({ lookupFailed: true, sourceAvailable: true }), 'access_temporary')
})
