import assert from 'node:assert/strict'
import test from 'node:test'
import { canonicalInboxReason, canonicalInboxStatus } from './inbox-compat'

test('maps canonical global intake states without changing lifecycle state', () => {
  assert.equal(canonicalInboxStatus('awaiting_upload'), 'pending_assignment')
  assert.equal(canonicalInboxStatus('uploaded'), 'analyzing')
  assert.equal(canonicalInboxStatus('validating'), 'analyzing')
  assert.equal(canonicalInboxStatus('processing'), 'analyzing')
  assert.equal(canonicalInboxStatus('ready'), 'ready_for_placement')
  assert.equal(canonicalInboxStatus('duplicate'), 'duplicate')
  assert.equal(canonicalInboxStatus('failed'), 'failed')
})

test('uses safe, actionable copy for canonical terminal states', () => {
  assert.equal(canonicalInboxReason('duplicate', 'duplicate'), 'This PDF already exists in this organisation. It was not added again.')
  assert.equal(canonicalInboxReason('failed', 'invalid_pdf'), 'This file is not a valid PDF. Choose a different PDF and try again.')
  assert.equal(canonicalInboxReason('failed', 'unknown_internal_code'), 'This intake could not be completed. Choose the PDF again or contact support.')
})
