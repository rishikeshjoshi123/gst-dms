import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { restoreBlockerMessage } from './restore-model'

test('restore blockers use safe, actionable, non-record-disclosing language', () => {
  assert.match(restoreBlockerMessage({
    status: 'restore_blocked', canRestore: false, blockerCode: 'parent_in_trash', blockingOperationId: 'operation-id',
  }), /parent Trash group first/)
  assert.match(restoreBlockerMessage({
    status: 'restore_blocked', canRestore: false, blockerCode: 'client_identifier_conflict', blockingOperationId: null,
  }), /GSTIN or PAN/)
  assert.doesNotMatch(restoreBlockerMessage({
    status: 'restore_blocked', canRestore: false, blockerCode: 'uniqueness_conflict', blockingOperationId: null,
  }), /[0-9a-f]{8}-[0-9a-f]{4}/i)
})

test('production callers use the typed Server Action and expose no permanent-delete control', () => {
  const action = readFileSync(new URL('../actions/trash.ts', import.meta.url), 'utf8')
  const control = readFileSync(new URL('../../components/trash/RestoreTrashOperationControl.tsx', import.meta.url), 'utf8')
  const strip = readFileSync(new URL('../../components/trash/TrashReadOnlyStrip.tsx', import.meta.url), 'utf8')
  const workspace = readFileSync(new URL('../../app/(app)/trash/TrashWorkspace.tsx', import.meta.url), 'utf8')

  assert.match(action, /^'use server'/)
  assert.match(action, /rpc\('restore_trash_operation'/)
  assert.match(action, /scheduleDocumentOutboxWake\(\)/)
  assert.doesNotMatch(action, /createServiceClient|\.from\('trash_operations'\)|\.from\('resource_trash_memberships'\)/)
  assert.match(control, /Restore group/)
  assert.match(control, /Independently trashed descendants stay/)
  assert.match(strip, /!inherited && context\.restorePreflight/)
  assert.match(workspace, /operation\.restorePreflight/)
  assert.doesNotMatch(`${control}\n${strip}\n${workspace}`, /Delete permanently/)
})

test('restore migration keeps RPC-only grants and durable identifier-only effects', () => {
  const migration = readFileSync(new URL('../../../supabase/migrations/00088_root_scoped_trash_restore.sql', import.meta.url), 'utf8')
  const dispatcher = readFileSync(new URL('../outbox/dispatcher.ts', import.meta.url), 'utf8')
  const trigger = readFileSync(new URL('../../trigger/outbox.ts', import.meta.url), 'utf8')
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.restore_trash_operation\(uuid,text\) TO authenticated/)
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.restore_trash_operation\(uuid,text\) FROM PUBLIC, anon, service_role/)
  assert.match(migration, /trash\.search_reindex_requested\.v1/)
  assert.match(migration, /trash\.schedule_reevaluation_requested\.v1/)
  assert.match(migration, /handle_trash_restore_effect/)
  assert.match(migration, /trash\.restore\.search\.run\./)
  assert.match(migration, /reminder_sent_30d=deadline\.reminder_sent_30d OR/)
  assert.match(migration, /pg_advisory_xact_lock\([\s\S]*?content_sha\.sha256/)
  assert.match(dispatcher, /trash\.operation_restored\.v1/)
  assert.match(dispatcher, /trash\.search_reindex_requested\.v1/)
  assert.match(dispatcher, /trash\.schedule_reevaluation_requested\.v1/)
  assert.match(trigger, /runTrashRestoreEffect/)
  assert.match(trigger, /documentLifecycleEvent\.triggerAndWait/)
  assert.doesNotMatch(migration, /signed.?url|raw_metadata|storage_path/)
})
