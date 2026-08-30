import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import {
  canonicalTrashResourcePath,
  describeIncludedItems,
  shapeTrashWorkspaceRows,
  type TrashWorkspaceProjectionRow,
} from './workspace-model'

const rootRow: TrashWorkspaceProjectionRow = {
  row_kind: 'operation',
  total_storage_bytes: 4096,
  operation_id: '85000000-0000-4000-8000-000000000001',
  root_resource_type: 'matter',
  root_resource_id: '85000000-0000-4000-8000-000000000002',
  root_membership_id: '85000000-0000-4000-8000-000000000003',
  root_name: 'Long matter identity',
  root_parent_context: 'Client identity',
  root_client_id: null,
  root_matter_id: '85000000-0000-4000-8000-000000000002',
  root_document_id: null,
  deleted_at: '2026-08-30T10:00:00.000Z',
  deleted_by_name: 'A team member',
  reason: 'Duplicate matter',
  included_client_count: 0,
  included_matter_count: 1,
  included_document_count: 1,
  operation_storage_bytes: 2048,
  member_membership_id: null,
  member_parent_membership_id: null,
  member_resource_type: null,
  member_resource_id: null,
  member_name: null,
  member_client_id: null,
  member_matter_id: null,
  member_document_id: null,
}

test('workspace shaping collapses projection rows and attaches only selected descendants', () => {
  const childRow: TrashWorkspaceProjectionRow = {
    ...rootRow,
    member_membership_id: '85000000-0000-4000-8000-000000000004',
    member_parent_membership_id: rootRow.root_membership_id,
    member_resource_type: 'document',
    member_resource_id: '85000000-0000-4000-8000-000000000005',
    member_name: 'Evidence.pdf',
    member_matter_id: rootRow.root_matter_id,
    member_document_id: '85000000-0000-4000-8000-000000000005',
  }
  const result = shapeTrashWorkspaceRows([
    { ...rootRow, row_kind: 'summary' },
    rootRow,
    childRow,
  ], rootRow.operation_id)

  assert.equal(result.operations.length, 1)
  assert.equal(result.selectedOperation?.includedItems.length, 1)
  assert.equal(result.selectedOperation?.includedItems[0]?.canonicalPath, `/matters/${rootRow.root_matter_id}/documents/${childRow.member_resource_id}`)
  assert.equal(result.totalStorageBytes, 4096)
  assert.equal(describeIncludedItems(result.operations[0]!), '1 document')
})

test('canonical paths use the existing Client, Matter, and Document route shapes', () => {
  assert.equal(canonicalTrashResourcePath('client', 'client-id', null), '/clients/client-id')
  assert.equal(canonicalTrashResourcePath('matter', 'matter-id', null), '/matters/matter-id')
  assert.equal(canonicalTrashResourcePath('document', 'document-id', 'matter-id'), '/matters/matter-id/documents/document-id')
  assert.equal(canonicalTrashResourcePath('document', 'document-id', null), '')
})

test('server and live UI sources preserve the read-only boundary', () => {
  const reader = readFileSync(new URL('./workspace.ts', import.meta.url), 'utf8')
  const ui = readFileSync(new URL('../../app/(app)/trash/TrashWorkspace.tsx', import.meta.url), 'utf8')
  const migration = readFileSync(new URL('../../../supabase/migrations/00085_trash_workspace_reader.sql', import.meta.url), 'utf8')

  assert.match(reader, /import 'server-only'/)
  assert.match(reader, /getCurrentOrgId\(\)/)
  assert.match(reader, /p_limit: 50/)
  assert.doesNotMatch(reader, /createServiceClient/)
  assert.match(ui, /Open read-only page/)
  assert.match(ui, /Open read-only \{typeLabel\[operation\.resourceType\]\.toLowerCase\(\)\}/)
  assert.match(ui, /hidden min-w-\[720px\] lg:block/)
  assert.match(ui, /space-y-3 p-3 lg:hidden/)
  assert.match(ui, /<Button type="submit"[\s\S]*?>Search<\/Button>/)
  assert.doesNotMatch(ui, />Restore group</)
  assert.doesNotMatch(ui, />Delete permanently</)
  assert.doesNotMatch(ui, /retention|legal hold|purge eligibility/i)
  assert.match(migration, /REVOKE ALL ON FUNCTION[\s\S]*PUBLIC, anon, service_role/)
  assert.match(migration, /GRANT EXECUTE ON FUNCTION[\s\S]*TO authenticated/)
  assert.doesNotMatch(migration, /object_key|storage_path|raw_metadata/)
})
