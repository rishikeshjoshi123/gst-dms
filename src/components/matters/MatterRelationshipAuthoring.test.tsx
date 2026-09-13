import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { canAddTimelineRelationship, proceedingIdentity, reconcileConfirmedRelationshipArchives, type RelationshipAuthoringContext } from '../../lib/matters/relationship-authoring'
const component = readFileSync(new URL('./MatterRelationshipAuthoring.tsx', import.meta.url), 'utf8')
const graph = readFileSync(new URL('./MatterTimelineGraphCanvas.tsx', import.meta.url), 'utf8')
test('confirmed archive reconciliation hides only the acknowledged ID/version across stale and fresh projections', () => {
  const first = { id: 'first', revision: 2, title: 'Same title' }
  const other = { id: 'other', revision: 2, title: 'Same title' }
  assert.deepEqual(reconcileConfirmedRelationshipArchives([first, other], {}), [first, other])
  const confirmed = { first: 2 }
  assert.deepEqual(reconcileConfirmedRelationshipArchives([first, other], confirmed), [other])
  assert.deepEqual(reconcileConfirmedRelationshipArchives([{ ...first, revision: 1 }, other], confirmed), [other])
  assert.deepEqual(reconcileConfirmedRelationshipArchives([other], confirmed), [other])
  const reactivated = { ...first, revision: 4 }
  assert.deepEqual(reconcileConfirmedRelationshipArchives([reactivated, other], confirmed), [reactivated, other])
  assert.deepEqual(reconcileConfirmedRelationshipArchives([], confirmed), [])
  assert.match(component, /if \(result.ok\) \{[\s\S]*onArchived\?\.\(relationship.id, relationship.revision\)/)
})
test('creation requires two eligible documents and a catalogue without hiding archive', () => {
  const document = { id: 'e0010000-0000-0000-0000-000000000001', title: 'Repeated title', referenceNumber: null, lifecycleRevision: 1 }
  const context: RelationshipAuthoringContext = { outcome: 'ok', relationship_source_revision: 'a'.repeat(32), documents: [document, { ...document, id: 'e0010000-0000-0000-0000-000000000002' }], relationship_types: [{ relationshipType: 'responds_to', catalogueVersion: 1, canonicalPhrase: 'responds to', progressionPhrase: 'answered by' }] }
  assert.equal(canAddTimelineRelationship(context), true)
  for (const documents of [[], [document]]) assert.equal(canAddTimelineRelationship({ ...context, documents }), false)
  assert.equal(canAddTimelineRelationship({ ...context, relationship_types: [] }), false)
  assert.equal(canAddTimelineRelationship(null), false)
  assert.match(component, /if \(!archive && !canAddTimelineRelationship\(context\)\) return null/)
  assert.match(graph, /canAddTimelineRelationship\(authoringContext\) && <Button/)
})
test('record identifiers distinguish duplicate titles without altering catalogue sentences', () => {
  assert.equal(proceedingIdentity({ id: 'e0010000-0000-0000-0000-000000000001', referenceNumber: ' REF-1 ' }), 'Reference: REF-1')
  assert.equal(proceedingIdentity({ id: 'e0010000-0000-0000-0000-000000000002', referenceNumber: null }), 'Record ID: …000000000002')
  assert.equal((component.match(/proceedingIdentity\(document\)/g) ?? []).length, 2)
  assert.match(component, /Source — .*proceedingIdentity\(sourceRecord\).*Target — .*proceedingIdentity\(targetRecord\)/)
  assert.match(component, /description=\{`\$\{identities\}/)
})
test('ordered accessible selectors exclude self and display catalogue-owned sentences', () => {
  assert.match(component, /1\. Choose source document/)
  assert.match(component, /2\. Choose target document/)
  assert.match(component, /document\.id !== sourceId/)
  assert.match(component, /disabled=\{pending \|\| !source\}/)
  assert.match(component, /\$\{source.title\} \$\{catalogue.canonicalPhrase\} \$\{target.title\}/)
  assert.match(component, /\$\{target.title\} \$\{catalogue.progressionPhrase\} \$\{source.title\}/)
  assert.match(component, /ConfirmDialog/)
  assert.doesNotMatch(component, /replaceAll|LinkCreationDialog|LinkDeletionDialog|document_links|useOptimistic/)
})
test('graph authoring is explicit, keyboard-cancellable, self-safe and does not mutate by drawing', () => {
  assert.match(graph, /1\. Choose the source document/)
  assert.match(graph, /2\. Choose the target document/)
  assert.match(graph, /authoring\.sourceId === id/)
  assert.match(graph, /event.key === 'Escape'/)
  assert.match(graph, /event.preventDefault\(\); event.stopPropagation\(\)/)
  assert.match(graph, /deleteKeyCode=\{null\}/)
  assert.doesNotMatch(graph, /onConnect=|onEdgesDelete=/)
})
test('unchanged payload keeps one UUID through response loss, and errors retain the draft', () => {
  assert.match(component, /request.current\?\.signature !== signature/)
  assert.match(component, /key: crypto.randomUUID\(\)/)
  assert.match(component, /const idempotencyKey = request.current.key/)
  assert.match(component, /if \(result.ok\) \{[\s\S]*setReason\(''\)/)
  const action = readFileSync(new URL('../../lib/actions/timeline-relationships.ts', import.meta.url), 'utf8')
  assert.match(action, /if \(result.refresh\).*refresh\(\)/)
  assert.match(component, /catch \{[\s\S]*setMessage[\s\S]*setConfirming\(false\)/)
  assert.match(component, /isPending=\{pending\}/)
  assert.match(component, /onConfirm=\{\(\) => startTransition\(submit\)\}/)
})
