import assert from 'node:assert/strict'
import test from 'node:test'

import { shapeTrashPurgeImpact } from './purge-model'

test('shapes only the content-free purge projection contract', () => {
  const impact = shapeTrashPurgeImpact({
    code: 'ready', operation_id: 'operation', root_resource_type: 'matter', root_resource_id: 'matter',
    root_name: 'Matter title', confirmation_text: 'MAT-001', included_client_count: 0,
    included_matter_count: 1, included_document_count: 3, unique_bytes: 1200,
    shared_bytes_retained: 400, hold_count: 0, active_export_count: 1, blocker_count: 1,
    blockers: [{ code: 'active_export', resourceType: 'document', resourceId: 'document' }],
    can_purge: false, impact_fingerprint: 'a'.repeat(64), impact_version: 1,
    operation_state: 'trashed', job_state: null, job_safe_error_code: null,
    scheduled_permanent_deletion_at: '2026-10-01T00:00:00Z', purged_at: null,
    object_key: 'must/not/escape.pdf', storage_path: 'must/not/escape.pdf',
  })

  assert.equal(impact?.confirmationText, 'MAT-001')
  assert.equal(impact?.documents, 3)
  assert.equal(impact?.uniqueBytes, 1200)
  assert.equal(impact?.sharedBytesRetained, 400)
  assert.deepEqual(impact?.blockers, [{ code: 'active_export', resourceType: 'document', resourceId: 'document' }])
  assert.equal('objectKey' in (impact ?? {}), false)
  assert.equal('storagePath' in (impact ?? {}), false)
})

test('rejects incomplete and malformed projection rows', () => {
  assert.equal(shapeTrashPurgeImpact({ operation_id: 'operation' }), null)
  assert.deepEqual(shapeTrashPurgeImpact({
    code: 'ready', operation_id: 'operation', root_resource_type: 'document', root_resource_id: 'document',
    impact_fingerprint: 'b'.repeat(64), operation_state: 'trashed', blockers: [null, 'bad', {}],
  })?.blockers, [])
})
