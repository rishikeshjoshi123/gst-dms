import assert from 'node:assert/strict'
import test from 'node:test'
import {
  isRetiredStagedNotification,
  RETIRED_STAGED_NOTIFICATION_COPY,
} from './staged-retirement'

test('classifies legacy staged notifications as retired, with no live route semantics', () => {
  assert.equal(isRetiredStagedNotification({ type: 'staged_doc_ready' }), true)
  assert.equal(isRetiredStagedNotification({ entity_type: 'staged_document' }), true)
  assert.equal(isRetiredStagedNotification({ type: 'document_ready', entity_type: 'document' }), false)
  assert.match(RETIRED_STAGED_NOTIFICATION_COPY.body, /No action is available/)
})
