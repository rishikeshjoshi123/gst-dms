import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { activateRelationshipSchema, archiveRelationshipSchema, relationshipAuthoringContextSchema, relationshipCommandResult } from '../matters/relationship-authoring'

const sourceId = 'e0010000-0000-0000-0000-000000000001'
const targetId = 'e0010000-0000-0000-0000-000000000003'
const input = { matterId: 'd0010000-0000-0000-0000-000000000001', sourceId, targetId, sourceRevision: 2, targetRevision: 1, relationshipType: 'responds_to', reason: '', idempotencyKey: 'f1550000-0000-4000-8000-000000000001' }
test('command validation accepts canonical fixture UUIDs and numeric lifecycle revisions only', () => {
  assert.equal(activateRelationshipSchema.safeParse(input).success, true)
  for (const changed of [{ targetId: sourceId }, { relationshipType: 'other' }, { relationshipType: 'refers_to' }, { sourceRevision: 'md5' }, { targetRevision: 0 }, { sourceRevision: Number.MAX_SAFE_INTEGER + 1 }, { matterId: '../foreign' }, { reason: 'x'.repeat(501) }, { reason: 'line\nbreak' }]) assert.equal(activateRelationshipSchema.safeParse({ ...input, ...changed }).success, false)
})
test('archive requires a bounded plain-text reason and exact subject revision', () => {
  const archive = { matterId: input.matterId, relationshipId: sourceId, revision: 1, reason: ' Reviewed interpretation ', idempotencyKey: input.idempotencyKey }
  assert.equal(archiveRelationshipSchema.parse(archive).reason, 'Reviewed interpretation')
  for (const changed of [{ reason: ' ' }, { revision: 0 }, { reason: 'embedded\tcontrol' }, { reason: 'x'.repeat(501) }]) assert.equal(archiveRelationshipSchema.safeParse({ ...archive, ...changed }).success, false)
})
test('authoring context fails closed on malformed or excessive projections', () => {
  const context = { outcome: 'ok', relationship_source_revision: 'a'.repeat(32), documents: [{ id: sourceId, title: 'Reply', referenceNumber: null, lifecycleRevision: 7 }], relationship_types: [{ relationshipType: 'responds_to', catalogueVersion: 1, canonicalPhrase: 'responds to', progressionPhrase: 'answered by' }] }
  assert.equal(relationshipAuthoringContextSchema.safeParse(context).success, true)
  assert.equal(relationshipAuthoringContextSchema.safeParse({ ...context, documents: [{ ...context.documents[0], lifecycleRevision: 'presentation-md5' }] }).success, false)
  assert.equal(relationshipAuthoringContextSchema.safeParse({ ...context, outcome: 'unavailable' }).success, false)
  assert.equal(relationshipAuthoringContextSchema.safeParse({ ...context, documents: Array(1001).fill(context.documents[0]) }).success, false)
})
test('every core RPC outcome has safe actionable text and replay refreshes', () => {
  const sql = readFileSync(new URL('../../../supabase/migrations/00146_effective_relationship_core.sql', import.meta.url), 'utf8')
  const codes = new Set([...sql.matchAll(/RETURN QUERY SELECT '([^']+)'/g)].map(match => match[1]))
  for (const code of codes) {
    if (code === 'unavailable') continue
    const result = relationshipCommandResult(code)
    assert.ok(result.message.length > 10)
    assert.equal(result.ok, code === 'ok')
    if (code !== 'ok') assert.notEqual(result.message, relationshipCommandResult('unknown').message)
  }
  assert.equal(relationshipCommandResult('conflict').refresh, true)
  assert.deepEqual(relationshipCommandResult('ok', true), { ok: true, message: 'The earlier change was saved.', refresh: true, replayed: true })
})
test('actions authenticate and use typed subject-bound canonical commands with safe results', () => {
  const action = readFileSync(new URL('./timeline-relationships.ts', import.meta.url), 'utf8')
  assert.equal((action.match(/auth.getUser\(\)/g) ?? []).length, 2)
  assert.match(action, /rpc\('activate_document_relationship'/)
  assert.match(action, /p_expected_source_revision: value.sourceRevision/)
  assert.match(action, /rpc\('archive_matter_timeline_relationship'/)
  assert.doesNotMatch(action, /\.from\(|service_role|document_links|error\.message/)
})
