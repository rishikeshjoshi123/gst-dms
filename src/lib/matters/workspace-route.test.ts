import assert from 'node:assert/strict'
import test from 'node:test'

import {
  buildMatterDocumentSelectionHref,
  buildMatterFilesPageHref,
  buildMatterInspectorHref,
  buildMatterSectionHref,
  buildMatterTimelineFiltersHref,
  buildMatterRelationshipSelectionHref,
  buildMatterTimelineViewHref,
  loadOnlyActiveMatterSection,
  MATTER_PRIMARY_MOBILE_SECTIONS,
  MATTER_SECONDARY_MOBILE_SECTIONS,
  MATTER_SECTION_IDS,
  matterTimelineGraphRequestKey,
  parseMatterWorkspaceRoute,
  searchParamEntries,
  shouldRequestMatterTimelineGraph,
  type MatterSectionId,
} from './workspace-route'
import { acceptedSectionSelection } from './workspace-selection'

const documentId = '00000000-0000-4000-8000-000000000001'
const defaultFilesPage = { offset: 0, limit: 50 }
const defaultTimelinePage = { offset: 0, limit: 50, filters: [] }

test('graph projection requests are permitted only for a new desktop-capable view', () => {
  assert.equal(shouldRequestMatterTimelineGraph(false, false), false)
  assert.equal(shouldRequestMatterTimelineGraph(false, true), false)
  assert.equal(shouldRequestMatterTimelineGraph(true, true), false)
  assert.equal(shouldRequestMatterTimelineGraph(true, false), true)
})

test('graph request identity is deterministic and collision-free for delimiter-bearing filters', () => {
  const left = matterTimelineGraphRequestKey('matter', 'revision', ['q:a|b', 'type:c'])
  const right = matterTimelineGraphRequestKey('matter', 'revision', ['q:a', 'type:b|c'])
  assert.notEqual(left, right)
  assert.equal(left, matterTimelineGraphRequestKey('matter', 'revision', ['q:a|b', 'type:c']))
})

test('uses the fixed canonical order and defaults invalid or omitted sections to Timeline', () => {
  assert.deepEqual(MATTER_SECTION_IDS, [
    'timeline', 'files', 'case-brief', 'notes', 'deadlines', 'financials', 'activity', 'details',
  ])
  assert.equal(parseMatterWorkspaceRoute({}).section, 'timeline')
  assert.equal(parseMatterWorkspaceRoute({ section: 'unknown' }).section, 'timeline')
  assert.equal(parseMatterWorkspaceRoute({ section: ['files', 'notes'] }).section, 'timeline')
  assert.equal(parseMatterWorkspaceRoute({ section: 'financials' }).section, 'financials')
  assert.equal(parseMatterWorkspaceRoute({}).timelineView, 'graph')
  assert.equal(parseMatterWorkspaceRoute({ view: 'chronology' }).timelineView, 'chronology')
  assert.equal(parseMatterWorkspaceRoute({ view: ['graph', 'chronology'] }).timelineView, 'graph')
  assert.equal(parseMatterWorkspaceRoute({ view: 'invalid' }).timelineView, 'graph')
  assert.equal(parseMatterWorkspaceRoute({ section: 'files', view: 'chronology' }).timelineView, 'graph')
})

test('parses selection only for Timeline or Files and rejects malformed or repeated ids', () => {
  assert.deepEqual(parseMatterWorkspaceRoute({ section: 'timeline', document: documentId, inspector: 'notes' }), {
    section: 'timeline', timelineView: 'graph', selectionRequested: true, selectedDocumentId: documentId, inspector: 'notes', filesPage: defaultFilesPage, timelinePage: defaultTimelinePage,
  })
  assert.equal(parseMatterWorkspaceRoute({ section: 'files', document: 'malformed' }).selectedDocumentId, null)
  assert.equal(parseMatterWorkspaceRoute({ section: 'files', document: [documentId, documentId] }).selectedDocumentId, null)
  assert.deepEqual(parseMatterWorkspaceRoute({ section: 'details', document: documentId, inspector: 'notes' }), {
    section: 'details', timelineView: 'graph', selectionRequested: false, selectedDocumentId: null, inspector: 'overview', filesPage: defaultFilesPage, timelinePage: defaultTimelinePage,
  })
})

test('parses bounded Timeline paging and repeated filters for the secured chronology reader', () => {
  assert.deepEqual(parseMatterWorkspaceRoute({ timelineOffset: '100', timelineLimit: '25', filter: ['incoming', 'q:%_\\'] }).timelinePage, { offset: 100, limit: 25, filters: ['incoming', 'q:%_\\'] })
  assert.deepEqual(parseMatterWorkspaceRoute({ timelineOffset: ['50', '100'], timelineLimit: '0', filter: ['x'.repeat(81)] }).timelinePage, defaultTimelinePage)
})

test('Timeline filter href applies and clears once while preserving unrelated repeated state', () => {
  const entries: Array<[string, string]> = [
    ['section', 'timeline'], ['view', 'chronology'], ['document', documentId],
    ['inspector', 'notes'], ['filter', 'incoming'], ['timelineOffset', '100'],
    ['timelineLimit', '25'], ['return', 'one'], ['return', 'two'],
  ]
  const applied = new URL(buildMatterTimelineFiltersHref('matter/one', entries, ['type:Notice', 'from:2026-01-01']), 'https://casechain.test')
  assert.equal(applied.pathname, '/matters/matter%2Fone')
  assert.deepEqual(applied.searchParams.getAll('filter'), ['type:Notice', 'from:2026-01-01'])
  assert.equal(applied.searchParams.has('timelineOffset'), false)
  assert.equal(applied.searchParams.get('timelineLimit'), '25')
  assert.equal(applied.searchParams.get('document'), documentId)
  assert.equal(applied.searchParams.get('inspector'), 'notes')
  assert.deepEqual(applied.searchParams.getAll('return'), ['one', 'two'])
  const cleared = new URL(buildMatterTimelineFiltersHref('matter/one', applied.searchParams.entries(), []), 'https://casechain.test')
  assert.equal(cleared.searchParams.has('filter'), false)
  assert.equal(cleared.searchParams.get('view'), 'chronology')
})

test('Timeline view and relationship hrefs replace owned state while preserving filters and selection context', () => {
  const entries: Array<[string, string]> = [
    ['section', 'timeline'], ['view', 'graph'], ['view', 'chronology'],
    ['filter', 'incoming'], ['document', documentId], ['inspector', 'notes'],
  ]
  const view = new URL(buildMatterTimelineViewHref('matter/one', entries, 'chronology'), 'https://casechain.test')
  assert.deepEqual(view.searchParams.getAll('view'), ['chronology'])
  assert.deepEqual(view.searchParams.getAll('filter'), ['incoming'])
  assert.equal(view.searchParams.get('document'), documentId)
  assert.equal(view.searchParams.get('inspector'), 'notes')

  const relationship = new URL(buildMatterRelationshipSelectionHref('matter/one', entries, documentId), 'https://casechain.test')
  assert.equal(relationship.searchParams.get('document'), documentId)
  assert.equal(relationship.searchParams.get('inspector'), 'relationships')
  assert.deepEqual(relationship.searchParams.getAll('filter'), ['incoming'])
})

test('parses bounded Files paging and fails repeated or malformed paging values closed', () => {
  assert.deepEqual(
    parseMatterWorkspaceRoute({ section: 'files', filesOffset: '100', filesLimit: '25' }).filesPage,
    { offset: 100, limit: 25 },
  )
  assert.deepEqual(
    parseMatterWorkspaceRoute({ section: 'files', filesOffset: '-1', filesLimit: '0' }).filesPage,
    defaultFilesPage,
  )
  assert.deepEqual(
    parseMatterWorkspaceRoute({ filesOffset: ['50', '100'], filesLimit: ['25', '50'] }).filesPage,
    defaultFilesPage,
  )
})

test('section hrefs preserve unrelated and repeated query state', () => {
  const entries = searchParamEntries({
    section: 'timeline',
    filter: ['review', 'failed'],
    from: 'review',
    view: 'chronology',
    document: documentId,
    inspector: 'notes',
  })
  const href = buildMatterSectionHref('matter/one', entries, 'activity')
  const url = new URL(href, 'https://casechain.test')
  assert.equal(url.pathname, '/matters/matter%2Fone')
  assert.deepEqual(url.searchParams.getAll('filter'), ['review', 'failed'])
  assert.equal(url.searchParams.get('from'), 'review')
  assert.equal(url.searchParams.get('section'), 'activity')
  assert.equal(url.searchParams.has('document'), false)
  assert.equal(url.searchParams.has('inspector'), false)
  assert.equal(url.searchParams.has('view'), false)
})

test('repeated section values use the same Timeline fallback when deciding whether to clear selection', () => {
  const href = buildMatterSectionHref('matter', [
    ['section', 'files'], ['section', 'notes'], ['document', documentId], ['inspector', 'notes'],
  ], 'files')
  const url = new URL(href, 'https://casechain.test')
  assert.equal(url.searchParams.get('section'), 'files')
  assert.equal(url.searchParams.has('document'), false)
  assert.equal(url.searchParams.has('inspector'), false)
})

test('sections without document inspectors clear inert selection state even on same-section navigation', () => {
  const href = buildMatterSectionHref('matter', [
    ['section', 'details'], ['document', documentId], ['inspector', 'notes'],
  ], 'details')
  const url = new URL(href, 'https://casechain.test')
  assert.equal(url.searchParams.has('document'), false)
  assert.equal(url.searchParams.has('inspector'), false)
})

test('selection hrefs preserve repeated params and clear inspector with the selection', () => {
  const entries: Array<[string, string]> = [
    ['section', 'files'], ['filter', 'one'], ['filter', 'two'], ['inspector', 'relationships'],
  ]
  const selected = new URL(buildMatterDocumentSelectionHref('matter', entries, documentId), 'https://casechain.test')
  assert.deepEqual(selected.searchParams.getAll('filter'), ['one', 'two'])
  assert.equal(selected.searchParams.get('document'), documentId)
  const cleared = new URL(buildMatterDocumentSelectionHref('matter', selected.searchParams.entries(), null), 'https://casechain.test')
  assert.equal(cleared.searchParams.has('document'), false)
  assert.equal(cleared.searchParams.has('inspector'), false)
})

test('inspector hrefs preserve selection and repeated query state', () => {
  const href = buildMatterInspectorHref('matter', [
    ['section', 'timeline'], ['document', documentId], ['filter', 'one'], ['filter', 'two'],
  ], 'relationships')
  const url = new URL(href, 'https://casechain.test')
  assert.equal(url.searchParams.get('document'), documentId)
  assert.equal(url.searchParams.get('inspector'), 'relationships')
  assert.deepEqual(url.searchParams.getAll('filter'), ['one', 'two'])
})

test('Files page hrefs replace owned paging keys and preserve selection, inspector, and repeated query state', () => {
  const href = buildMatterFilesPageHref('matter/one', [
    ['section', 'files'],
    ['document', documentId],
    ['inspector', 'notes'],
    ['filter', 'evidence'],
    ['filter', 'correspondence'],
    ['filesOffset', '0'],
    ['filesOffset', '999'],
    ['filesLimit', '10'],
  ], { offset: 50, limit: 50 })
  const url = new URL(href, 'https://casechain.test')
  assert.equal(url.pathname, '/matters/matter%2Fone')
  assert.equal(url.searchParams.get('section'), 'files')
  assert.equal(url.searchParams.get('filesOffset'), '50')
  assert.equal(url.searchParams.has('filesLimit'), false)
  assert.equal(url.searchParams.get('document'), documentId)
  assert.equal(url.searchParams.get('inspector'), 'notes')
  assert.deepEqual(url.searchParams.getAll('filter'), ['evidence', 'correspondence'])
})

test('mobile uses four direct sections plus More for the fixed four secondary sections', () => {
  assert.deepEqual(MATTER_PRIMARY_MOBILE_SECTIONS, ['timeline', 'files', 'case-brief', 'notes'])
  assert.deepEqual(MATTER_SECONDARY_MOBILE_SECTIONS, ['deadlines', 'financials', 'activity', 'details'])
})

test('the active-section dispatcher invokes exactly one loader', async () => {
  const called: MatterSectionId[] = []
  const loaders = Object.fromEntries(MATTER_SECTION_IDS.map((section) => [section, async () => {
    called.push(section)
    return section
  }])) as Record<MatterSectionId, () => Promise<MatterSectionId>>
  assert.equal(await loadOnlyActiveMatterSection('notes', loaders), 'notes')
  assert.deepEqual(called, ['notes'])
})

test('selection acceptance fails closed for inaccessible, cross-matter, and wrong-class ids', () => {
  const documents = [
    { id: documentId, matter_id: 'matter-a', document_class: 'proceeding' },
    { id: '00000000-0000-4000-8000-000000000002', matter_id: 'matter-a', document_class: 'supporting' },
    { id: '00000000-0000-4000-8000-000000000003', matter_id: 'matter-b', document_class: 'proceeding' },
  ]
  assert.equal(acceptedSectionSelection(documentId, 'matter-a', 'proceeding', documents)?.id, documentId)
  assert.equal(acceptedSectionSelection('00000000-0000-4000-8000-000000000004', 'matter-a', 'proceeding', [
    ...documents,
    { id: '00000000-0000-4000-8000-000000000004', matter_id: 'matter-a', document_class: null },
  ])?.id, '00000000-0000-4000-8000-000000000004')
  assert.equal(acceptedSectionSelection('00000000-0000-4000-8000-000000000099', 'matter-a', 'proceeding', documents), null)
  assert.equal(acceptedSectionSelection(documents[1].id, 'matter-a', 'proceeding', documents), null)
  assert.equal(acceptedSectionSelection(documents[2].id, 'matter-a', 'proceeding', documents), null)
})
