import assert from 'node:assert/strict'
import test from 'node:test'
import { clampMatterTimelineOffset, createMatterTimelineSnapshotPage, describeMatterTimelineRelationship, isMatterTimelineFilter, matterTimelineVisibleRange, normalizeMatterTimelinePage, shapeMatterTimelineRelationships, shapeMatterTimelineSnapshotMetadata } from './workspace-timeline-page'

test('chronology paging rejects malformed input and caps hostile input', () => {
  assert.deepEqual(normalizeMatterTimelinePage({ offset: '-1', limit: '0', filters: ['x'.repeat(81), 'incoming', 'incoming'] }), { offset: 0, limit: 50, filters: [] })
  assert.deepEqual(normalizeMatterTimelinePage({ offset: '9999999999', limit: '999', filters: ['q:%_\\'] }), { offset: 1000000, limit: 100, filters: ['q:%_\\'] })
})
test('filter grammar accepts only authoritative URL filters and validates calendar dates', () => {
  for (const filter of ['q:%_\\', `q:${'q'.repeat(75)}`, `q:${'q'.repeat(76)}`, `q:${'q'.repeat(78)}`, 'type:notice', 'from:2026-02-28', 'to:2026-12-31', 'attention:pdf-not-attached']) assert.equal(isMatterTimelineFilter(filter), true)
  for (const filter of [`q:${'q'.repeat(79)}`, 'from:2026-99-99', 'to:2026-02-30', 'type:', 'relationship:linked', 'q:', 'deadline:today', 'q: leading', 'q:trailing ', 'type: leading', 'type:trailing ', 'q:line\nbreak', 'type:tab\tvalue', `q:null\u0000value`]) assert.equal(isMatterTimelineFilter(filter), false)
})
test('conflicting or duplicate singleton filters and reversed dates normalize to no filters', () => {
  for (const filters of [
    ['incoming', 'outgoing'], ['dated', 'undated'], ['q:one', 'q:two'],
    ['type:notice', 'type:order'], ['attention:review', 'attention:failed'],
    ['from:2026-02-01', 'from:2026-02-02'], ['to:2026-02-01', 'to:2026-02-02'],
    ['from:2026-03-01', 'to:2026-02-01'], ['incoming', 'incoming'],
  ]) assert.deepEqual(normalizeMatterTimelinePage({ filters }).filters, [])
})
test('chronology clamps stale offsets and reports exact ranges', () => {
  assert.equal(clampMatterTimelineOffset(250, 50, 250), 200)
  assert.equal(clampMatterTimelineOffset(0, 50, 0), 0)
  assert.deepEqual(matterTimelineVisibleRange({ offset: 200, total: 250, items: Array(50) }), { start: 201, end: 250 })
})

test('relationship projection shaping preserves catalogue phrases and both directions', () => {
  const relationship = {
    id: 'relationship-a', revision: 2,
    canonicalSourceDocumentId: 'reply', canonicalTargetDocumentId: 'notice',
    displayFromDocumentId: 'notice', displayToDocumentId: 'reply',
    relationshipType: 'responds_to', canonicalPhrase: 'responds to',
    progressionPhrase: 'answered by', verification: 'human',
    canonicalSourceTitle: 'Reply', canonicalTargetTitle: 'Show Cause Notice',
  }
  const shaped = shapeMatterTimelineRelationships([
    relationship,
    { ...relationship, id: 'legacy', relationshipType: 'summarizes' },
    { ...relationship, id: 'reversed', displayFromDocumentId: 'reply' },
  ])
  assert.deepEqual(shaped, [relationship])
  assert.deepEqual(describeMatterTimelineRelationship(shaped[0], 'reply'), {
    direction: 'outgoing',
    canonicalSentence: 'Reply responds to Show Cause Notice.',
    progressionSentence: 'Show Cause Notice answered by Reply.',
  })
  assert.equal(describeMatterTimelineRelationship(shaped[0], 'notice').direction, 'incoming')
  assert.equal(describeMatterTimelineRelationship(shaped[0], 'other').direction, null)
})

test('Trash chronology uses exact-current metadata, deterministic ordering, filters, paging and fenced selection', () => {
  const matterId = 'matter-a'
  const documents = [
    { id: 'b', matter_id: matterId, document_class: 'proceeding', display_title: 'Second', status: 'uploaded', current_version_id: 'vb', content_availability: 'source_attached', doc_type: 'Forbidden legacy type', reference_number: 'FORBIDDEN/B', doc_date: '2020-01-01', direction: 'incoming', has_any_version: true, created_at: '2026-01-02T00:00:00Z' },
    { id: 'a', matter_id: matterId, document_class: 'proceeding', display_title: 'First', status: 'placed', current_version_id: 'va', content_availability: 'source_indexed', doc_type: 'Forbidden legacy type', reference_number: 'FORBIDDEN/A', doc_date: '2020-01-01', direction: 'outgoing', has_any_version: true, created_at: '2026-01-01T00:00:00Z' },
    { id: 'c', matter_id: matterId, document_class: null, display_title: 'Command-authored', status: 'failed', current_version_id: null, content_availability: 'metadata_only', doc_type: 'Command type', reference_number: 'COMMAND/C', doc_date: '2026-03-01', direction: 'incoming', has_any_version: false, created_at: '2026-01-03T00:00:00Z' },
    { id: 'd', matter_id: matterId, document_class: 'proceeding', display_title: 'Historical version', status: 'placed', current_version_id: null, content_availability: 'metadata_only', doc_type: 'Must not fall back', reference_number: 'FORBIDDEN/D', doc_date: '2026-04-01', direction: 'outgoing', has_any_version: true, created_at: '2026-01-04T00:00:00Z' },
    { id: 'supporting', matter_id: matterId, document_class: 'supporting', display_title: 'Excluded', status: 'placed', current_version_id: null, content_availability: 'metadata_only', doc_type: null, reference_number: null, doc_date: null, direction: null, has_any_version: false, created_at: '2026-01-05T00:00:00Z' },
    { id: 'foreign', matter_id: 'matter-b', document_class: 'proceeding', display_title: 'Excluded', status: 'placed', current_version_id: null, content_availability: 'metadata_only', doc_type: null, reference_number: null, doc_date: null, direction: null, has_any_version: false, created_at: '2026-01-05T00:00:00Z' },
  ]
  const metadata = {
    a: { state: 'available' as const, documentVersionId: 'va', docType: 'Notice', referenceNumber: 'REF/A', documentDate: '2026-02-01', direction: 'incoming' },
    b: { state: 'available' as const, documentVersionId: 'vb', docType: 'Order', referenceNumber: 'REF/B', documentDate: '2026-02-01', direction: 'outgoing' },
    c: { state: 'available' as const, documentVersionId: 'stale', docType: 'Stale', referenceNumber: 'STALE', documentDate: '2020-01-01', direction: 'incoming' },
  }
  const page = createMatterTimelineSnapshotPage(matterId, documents, metadata, { limit: 1, offset: 99, filters: ['type:notice'] }, 'c')
  assert.equal(page.total, 1)
  assert.equal(page.unfilteredTotal, 4)
  assert.equal(page.offset, 0)
  assert.deepEqual(page.items.map((item) => item.id), ['a'])
  assert.equal(page.selected?.id, 'c')
  assert.equal(page.selected?.documentType, 'Command type')
  assert.equal(page.selected?.referenceNumber, 'COMMAND/C')
  assert.equal(page.selected?.contentAvailability, 'metadata_only')
  assert.equal(page.items[0].contentAvailability, 'source_indexed')
  assert.equal(page.items[0].attentionState, 'none')
  assert.ok(page.sourceRevision)

  const all = createMatterTimelineSnapshotPage(matterId, documents, metadata, {}, 'supporting')
  assert.deepEqual(all.items.map((item) => item.id), ['a', 'b', 'c', 'd'])
  assert.equal(all.selected, null)
  assert.equal(all.items.find((item) => item.id === 'd')?.documentType, null)
  assert.equal(all.items.find((item) => item.id === 'd')?.referenceNumber, null)
  assert.equal(createMatterTimelineSnapshotPage(matterId, documents, metadata, { filters: ['q:notice'] }).total, 0)
  assert.equal(createMatterTimelineSnapshotPage(matterId, documents, metadata, { filters: ['type:notice'] }).total, 1)
  assert.equal(createMatterTimelineSnapshotPage(matterId, documents, metadata, { filters: ['attention:processing'] }).items[0]?.id, 'b')
  assert.equal(createMatterTimelineSnapshotPage(matterId, documents, metadata, { filters: ['attention:pdf-not-attached'] }).total, 2)
})

test('Trash chronology revisions are stable and change with authorised snapshot identity', () => {
  const document = { id: 'a', matter_id: 'matter-a', document_class: 'proceeding', display_title: 'First', status: 'placed', current_version_id: 'va', content_availability: 'source_indexed', doc_type: 'Forbidden legacy type', reference_number: 'FORBIDDEN/A', doc_date: '2020-01-01', direction: 'outgoing', has_any_version: true, created_at: '2026-01-01T00:00:00Z' }
  const metadata = { a: { state: 'available' as const, documentVersionId: 'va', docType: 'Notice', referenceNumber: 'REF/A', documentDate: '2026-02-01', direction: 'incoming' } }
  const first = createMatterTimelineSnapshotPage('matter-a', [document], metadata)
  const repeated = createMatterTimelineSnapshotPage('matter-a', [document], metadata)
  const changed = createMatterTimelineSnapshotPage('matter-a', [{ ...document, status: 'needs_review' }], metadata)
  assert.equal(first.sourceRevision, repeated.sourceRevision)
  assert.equal(first.items[0].revision, repeated.items[0].revision)
  assert.notEqual(first.sourceRevision, changed.sourceRevision)
  assert.notEqual(first.items[0].revision, changed.items[0].revision)
})

test('Trash metadata shaping requires one exact-current well-typed value per field', () => {
  const rows = [
    { document_id: 'a', document_version_id: 'va', field_path: 'document.type', value_type: 'code', normalized_value: 'Notice', resolution: 'automatic' },
    { document_id: 'a', document_version_id: 'va', field_path: 'document.type', value_type: 'text', normalized_value: 'Malformed sibling', resolution: 'automatic' },
    { document_id: 'a', document_version_id: 'va', field_path: 'document.reference_number', value_type: 'code', normalized_value: 'REF/A', resolution: 'corrected' },
    { document_id: 'a', document_version_id: 'va', field_path: 'document.date', value_type: 'date', normalized_value: '2026-02-30', resolution: 'automatic' },
    { document_id: 'a', document_version_id: 'va', field_path: 'document.direction', value_type: 'code', normalized_value: 'sideways', resolution: 'automatic' },
  ]
  const metadata = shapeMatterTimelineSnapshotMetadata(['a'], rows).a
  assert.equal(metadata.state, 'available')
  assert.equal(metadata.documentVersionId, 'va')
  assert.equal(metadata.docType, null)
  assert.equal(metadata.referenceNumber, 'REF/A')
  assert.equal(metadata.documentDate, null)
  assert.equal(metadata.direction, null)
  assert.equal(shapeMatterTimelineSnapshotMetadata(['missing'], rows).missing.state, 'unavailable')
})
