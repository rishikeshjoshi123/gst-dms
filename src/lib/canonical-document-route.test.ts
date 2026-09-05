import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { canonicalDocumentPath } from './canonical-document-route'

test('builds the canonical active document route without matter lineage', () => {
  assert.equal(canonicalDocumentPath('document-id'), '/documents/document-id')
  assert.equal(canonicalDocumentPath('document/one'), '/documents/document%2Fone')
})

test('preserves only explicit scalar matter context for exact Trash lineage', () => {
  assert.equal(
    canonicalDocumentPath('document-id', { matterId: 'matter one' }),
    '/documents/document-id?matterId=matter+one',
  )
  assert.equal(canonicalDocumentPath('document-id', { matterId: ['matter-a', 'matter-b'] }), '/documents/document-id')
  assert.equal(canonicalDocumentPath('document-id', { matterId: '' }), '/documents/document-id')
})

test('active document callers use the canonical route while Trash keeps lineage compatibility', () => {
  const activeCallers = [
    './actions/search.ts',
    './actions/trash.ts',
    '../components/matters/TimelineDocumentDetail.tsx',
    '../components/matters/TimelineGraphNode.tsx',
    '../components/matters/MatterTabs.tsx',
    '../components/matters/MatterNotesTab.tsx',
    '../app/(app)/notes/NotesClientView.tsx',
    '../app/(app)/inbox/InboxClientView.tsx',
    '../app/(app)/notifications/NotificationsClientView.tsx',
  ].map((relativePath) => readFileSync(new URL(relativePath, import.meta.url), 'utf8'))

  for (const source of activeCallers) {
    assert.match(source, /canonicalDocumentPath/)
    assert.doesNotMatch(source, /`\/matters\/\$\{[^`]+\/documents\/\$\{/)
  }

  const trashWorkspace = readFileSync(new URL('./trash/workspace-model.ts', import.meta.url), 'utf8')
  assert.match(trashWorkspace, /matterId \? canonicalDocumentPath\(resourceId, \{ matterId \}\) : ''/)
})

test('notifications route active documents canonically without changing other entity handling', () => {
  const source = readFileSync(new URL('../app/(app)/notifications/NotificationsClientView.tsx', import.meta.url), 'utf8')

  assert.match(source, /if \(isRetiredStagedNotification\(n\)\) return null/)
  assert.match(source, /if \(!n\.entity_id\) return null/)
  assert.match(source, /if \(n\.entity_type === 'document'\) return canonicalDocumentPath\(n\.entity_id\)/)
  assert.match(source, /if \(n\.entity_type === 'matter'\) return `\/matters\/\$\{n\.entity_id\}`/)
  assert.match(source, /if \(n\.entity_type === 'case_note'\) return `\/notes`/)
})

test('matter read-only compositions preserve each document Trash lineage without affecting active links', () => {
  const matterTabs = readFileSync(new URL('../components/matters/MatterTabs.tsx', import.meta.url), 'utf8')
  const graphNode = readFileSync(new URL('../components/matters/TimelineGraphNode.tsx', import.meta.url), 'utf8')
  const notesTab = readFileSync(new URL('../components/matters/MatterNotesTab.tsx', import.meta.url), 'utf8')
  const timelineGraph = readFileSync(new URL('../components/matters/TimelineGraph.tsx', import.meta.url), 'utf8')

  assert.match(matterTabs, /canonicalDocumentPath\(doc\.id, readOnly \? \{ matterId: doc\.matter_id \} : \{\}\)/)
  assert.match(graphNode, /canonicalDocumentPath\(doc\.id, readOnly \? \{ matterId: doc\.matter_id \} : \{\}\)/)
  assert.match(timelineGraph, /data:\s*\{[\s\S]*doc,[\s\S]*readOnly,[\s\S]*\}/)
  assert.match(notesTab, /documents\.find\(document => document\.id === selectedThread\?\.document_id\)\?\.matter_id/)
  assert.match(notesTab, /canonicalDocumentPath\(selectedThread\.document_id, readOnly \? \{ matterId: selectedThreadDocumentMatterId \} : \{\}\)/)
  assert.match(notesTab, /canonicalDocumentPath\(selectedThread\.document_id, readOnly \? \{ matterId: selectedThreadDocumentMatterId \} : \{\}\)\}#page=/)

  assert.equal(canonicalDocumentPath('active-document'), '/documents/active-document')
  assert.equal(
    canonicalDocumentPath('trashed-document', { matterId: 'its-own-matter' }),
    '/documents/trashed-document?matterId=its-own-matter',
  )
})
