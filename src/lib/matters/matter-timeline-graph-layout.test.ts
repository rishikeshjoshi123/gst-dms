import assert from 'node:assert/strict'
import test from 'node:test'

import {
  layoutMatterTimelineGraph,
  MATTER_TIMELINE_NODE_HEIGHT,
  MATTER_TIMELINE_NODE_WIDTH,
  shapeMatterTimelineGraphRelationshipProjection,
  shapeMatterTimelineGraphRelationships,
} from './matter-timeline-graph-layout'
import type { MatterTimelineChronologyItem, MatterTimelineRelationship } from './workspace-timeline-page'

function document(id: string, effectiveDate: string | null = '2026-01-01'): MatterTimelineChronologyItem {
  return {
    id, title: `Proceeding ${id}`, documentType: 'Order', referenceNumber: `REF/${id}`,
    effectiveDate, direction: 'incoming', classificationState: 'canonical',
    contentAvailability: 'source_indexed', attentionState: 'none', revision: `revision-${id}`,
  }
}

function relationship(
  id: string,
  source: string,
  target: string,
  relationshipType: MatterTimelineRelationship['relationshipType'] = 'responds_to',
  progressionPhrase = 'answered by',
): MatterTimelineRelationship {
  return {
    id, revision: 1, canonicalSourceDocumentId: source, canonicalTargetDocumentId: target,
    displayFromDocumentId: target, displayToDocumentId: source, relationshipType,
    canonicalPhrase: 'responds to', progressionPhrase, verification: 'human',
    canonicalSourceTitle: `Proceeding ${source}`, canonicalTargetTitle: `Proceeding ${target}`,
  }
}

function assertNoOverlap(nodes: ReturnType<typeof layoutMatterTimelineGraph>['nodes']) {
  for (let leftIndex = 0; leftIndex < nodes.length; leftIndex += 1) {
    for (let rightIndex = leftIndex + 1; rightIndex < nodes.length; rightIndex += 1) {
      const left = nodes[leftIndex]
      const right = nodes[rightIndex]
      const separated = left.position.x + left.width <= right.position.x
        || right.position.x + right.width <= left.position.x
        || left.position.y + left.height <= right.position.y
        || right.position.y + right.height <= left.position.y
      assert.equal(separated, true, `${left.id} overlaps ${right.id}`)
    }
  }
}

test('0 and 1 node layouts retain the exact fixed dimensions', () => {
  assert.deepEqual(layoutMatterTimelineGraph([], []), {
    nodes: [], edges: [], width: 280, height: 216, unlinkedLaneY: null,
  })
  const one = layoutMatterTimelineGraph([document('one')], [])
  assert.equal(one.nodes[0].width, MATTER_TIMELINE_NODE_WIDTH)
  assert.equal(one.nodes[0].height, MATTER_TIMELINE_NODE_HEIGHT)
  assert.equal(one.nodes[0].unlinked, true)
  assertNoOverlap(one.nodes)
})

test('branch, merge, disconnected, undated and same-day peers are stable and non-overlapping', () => {
  const documents = [
    document('root', '2026-01-01'), document('branch-a', '2026-01-02'),
    document('branch-b', '2026-01-02'), document('merge', '2026-01-03'),
    document('disconnected', '2026-01-04'), document('undated', null),
  ]
  const relationships = [
    relationship('r1', 'branch-a', 'root'), relationship('r2', 'branch-b', 'root'),
    relationship('r3', 'merge', 'branch-a'), relationship('r4', 'merge', 'branch-b'),
  ]
  const first = layoutMatterTimelineGraph(documents, relationships)
  const repeated = layoutMatterTimelineGraph(documents, relationships)
  assert.deepEqual(first, repeated)
  assertNoOverlap(first.nodes)
  assert.ok((first.nodes.find((node) => node.id === 'root')?.position.x ?? Infinity)
    < (first.nodes.find((node) => node.id === 'merge')?.position.x ?? -Infinity))
  assert.ok((first.nodes.find((node) => node.id === 'disconnected')?.position.x ?? Infinity)
    < (first.nodes.find((node) => node.id === 'undated')?.position.x ?? -Infinity))
  assert.equal(first.nodes.find((node) => node.id === 'disconnected')?.unlinked, true)
})

test('same-rank siblings keep effective-date then ID visual order after Dagre', () => {
  const documents = [
    document('root', '2026-01-01'),
    document('jan-04', '2026-01-04'),
    document('jan-02-b', '2026-01-02'),
    document('jan-03', '2026-01-03'),
    document('jan-02-a', '2026-01-02'),
  ]
  const relationships = documents.slice(1).map((item, index) => relationship(
    `rank-${index}`,
    item.id,
    'root',
  ))
  const layout = layoutMatterTimelineGraph(documents, relationships)
  const siblings = layout.nodes
    .filter((node) => node.id !== 'root')
    .sort((left, right) => left.position.y - right.position.y)
  assert.deepEqual(siblings.map((node) => node.id), ['jan-02-a', 'jan-02-b', 'jan-03', 'jan-04'])
  assert.equal(new Set(siblings.map((node) => node.position.x)).size, 1)
  assertNoOverlap(layout.nodes)
})

test('strict graph relationship shaping rejects a partially malformed secured projection', () => {
  const valid = relationship(
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000003',
  )
  assert.deepEqual(shapeMatterTimelineGraphRelationships([valid]), { outcome: 'ok', relationships: [valid] })
  const malformed = [
    { ...valid, id: null },
    { ...valid, id: '' },
    { ...valid, id: 'not-a-uuid' },
    { ...valid, canonicalSourceDocumentId: '', displayToDocumentId: '' },
    { ...valid, canonicalTargetDocumentId: 'not-a-uuid', displayFromDocumentId: 'not-a-uuid' },
    { ...valid, displayFromDocumentId: valid.canonicalSourceDocumentId },
    { ...valid, canonicalPhrase: '   ' },
    { ...valid, progressionPhrase: '\t' },
    { ...valid, canonicalSourceTitle: '' },
    { ...valid, canonicalTargetTitle: '  Untitled proceeding' },
    { ...valid, revision: 0 },
    { ...valid, relationshipType: 'unknown' },
    { ...valid, verification: 'unknown' },
  ]
  for (const candidate of malformed) {
    assert.deepEqual(shapeMatterTimelineGraphRelationships([valid, candidate]), { outcome: 'unavailable', relationships: [] })
  }
  assert.deepEqual(shapeMatterTimelineGraphRelationships([valid, valid]), { outcome: 'unavailable', relationships: [] })
  assert.deepEqual(shapeMatterTimelineGraphRelationships({ relationships: [valid] }), { outcome: 'unavailable', relationships: [] })
})

test('strict graph projection rejects invalid successful-row revision and fetch metadata', () => {
  const valid = relationship(
    '10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000003',
  )
  const row = {
    outcome: 'ok', relationships: [valid], source_revision: 'a'.repeat(32), fetched_at: '2026-09-12T00:00:00.000Z',
  }
  assert.deepEqual(shapeMatterTimelineGraphRelationshipProjection(row), {
    outcome: 'ok', relationships: [valid], sourceRevision: 'a'.repeat(32), fetchedAt: '2026-09-12T00:00:00.000Z',
  })
  for (const malformed of [
    { ...row, source_revision: null },
    { ...row, source_revision: undefined },
    { ...row, source_revision: 7 },
    { ...row, source_revision: '' },
    { ...row, source_revision: 'revision' },
    { ...row, source_revision: 'A'.repeat(32) },
    { ...row, fetched_at: undefined },
    { ...row, fetched_at: null },
    { ...row, fetched_at: '' },
    { ...row, fetched_at: 'not-a-date' },
    { ...row, fetched_at: '2026-02-30T00:00:00Z' },
  ]) {
    assert.deepEqual(shapeMatterTimelineGraphRelationshipProjection(malformed), {
      outcome: 'unavailable', relationships: [], sourceRevision: null, fetchedAt: null,
    })
  }
})

test('multiple effective types are one progression edge with the catalogue-first phrase and full list', () => {
  const documents = [document('notice'), document('reply', '2026-01-02')]
  const relationships = [
    relationship('priority', 'reply', 'notice', 'responds_to', 'answered by'),
    relationship('secondary', 'reply', 'notice', 'arises_from', 'gave rise to'),
  ]
  const layout = layoutMatterTimelineGraph(documents, relationships)
  assert.equal(layout.edges.length, 1)
  assert.equal(layout.edges[0].displayFromDocumentId, 'notice')
  assert.equal(layout.edges[0].displayToDocumentId, 'reply')
  assert.equal(layout.edges[0].canonicalSourceDocumentId, 'reply')
  assert.equal(layout.edges[0].label, 'answered by +1')
  assert.deepEqual(layout.edges[0].relationships.map((item) => item.id), ['priority', 'secondary'])
})

test('relationships disappear instead of reconnecting when either filtered endpoint is absent', () => {
  const documents = [document('notice'), document('reply'), document('order')]
  const relationships = [
    relationship('reply-notice', 'reply', 'notice'),
    relationship('order-reply', 'order', 'reply'),
  ]
  const filtered = layoutMatterTimelineGraph(documents.slice(0, 2), relationships)
  assert.deepEqual(filtered.edges.map((edge) => edge.id), ['timeline-edge:notice:reply'])
  assert.equal(filtered.nodes.some((node) => node.id === 'order'), false)
})

for (const count of [10, 50, 100, 250]) {
  test(`${count}-node layout is deterministic, complete and non-overlapping`, () => {
    const documents = Array.from({ length: count }, (_, index) => document(
      `node-${String(index).padStart(3, '0')}`,
      index % 11 === 0 ? null : `2026-01-${String((index % 28) + 1).padStart(2, '0')}`,
    ))
    const relationships = documents.slice(1).map((item, index) => relationship(
      `relationship-${index}`,
      item.id,
      documents[index].id,
    ))
    const first = layoutMatterTimelineGraph(documents, relationships)
    assert.deepEqual(first, layoutMatterTimelineGraph(documents, relationships))
    assert.equal(first.nodes.length, count)
    assert.equal(first.edges.length, Math.max(0, count - 1))
    assertNoOverlap(first.nodes)
  })
}
