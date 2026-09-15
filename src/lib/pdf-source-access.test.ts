import assert from 'node:assert/strict'
import test from 'node:test'

import { pdfSignedHeadFailureCode, pdfSourceLookupFailureCode, pdfStorageFailureCode } from './pdf-source-access'

test('distinguishes a temporary lookup failure from a proven unavailable source', () => {
  assert.equal(pdfSourceLookupFailureCode({ lookupFailed: true, sourceAvailable: false }), 'access_temporary')
  assert.equal(pdfSourceLookupFailureCode({ lookupFailed: false, sourceAvailable: false }), 'source_unavailable')
  assert.equal(pdfSourceLookupFailureCode({ lookupFailed: false, sourceAvailable: true }), null)
  assert.equal(pdfSourceLookupFailureCode({ lookupFailed: true, sourceAvailable: true }), 'access_temporary')
})

test('private signed-source HEAD releases only a reachable locator', () => {
  assert.equal(pdfSignedHeadFailureCode(200), null)
  assert.equal(pdfSignedHeadFailureCode(204), null)
  assert.equal(pdfSignedHeadFailureCode(404), 'source_unavailable')
  for (const status of [400, 401, 403, 405, 500, 503]) {
    assert.equal(pdfSignedHeadFailureCode(status), 'access_temporary')
  }
})

test('only trusted Storage 404 proves missing object bytes', () => {
  assert.equal(pdfStorageFailureCode({ status: 404, message: 'private path' }), 'source_unavailable')
  assert.equal(pdfStorageFailureCode({ status: 400, statusCode: '404', message: 'private path' }), 'source_unavailable')
  assert.equal(pdfStorageFailureCode({ status: 400, statusCode: '400', message: 'private path' }), 'access_temporary')
  for (const status of [401, 403, 408, 500, 503]) {
    assert.equal(pdfStorageFailureCode({ status }), 'access_temporary')
  }
  assert.equal(pdfStorageFailureCode({ message: '404 private path' }), 'access_temporary')
  assert.equal(pdfStorageFailureCode(new TypeError('network')), 'access_temporary')
})
