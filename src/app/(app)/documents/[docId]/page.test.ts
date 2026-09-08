import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { documentInspectorIds } from '@/lib/documents/document-inspector-ids'

test('standalone inspector supplies selected and linked document projection IDs without duplicates', () => {
  assert.deepEqual(
    documentInspectorIds('selected', [{ id: 'selected' }, { id: 'linked-corrected' }, { id: 'linked-cleared' }]),
    ['selected', 'linked-corrected', 'linked-cleared'],
  )
})

test('canonical document route allowlists source state and preserves exact canonical Trash lineage', () => {
  const source = readFileSync(new URL('./page.tsx', import.meta.url), 'utf8')

  assert.match(source, /parseCanonicalDocumentUrlState\(query\)/)
  assert.match(source, /const expectedMatterId = sourceLocator\.matterId/)
  assert.match(source, /getCanonicalAssignedDocument\(docId, expectedMatterId\)/)
  assert.match(source, /const selectedVersionId = sourceLocator\.versionId \?\? doc\.current_version_id/)
  assert.match(source, /getCanonicalDocumentVersionSignedUrl\([\s\S]*docId,[\s\S]*selectedVersionId,[\s\S]*isTrashReadOnly \? exactDocument\.expectedMatterId : undefined/)
  assert.match(source, /getDocumentsByMatter\(matterId\)/)
  assert.doesNotMatch(source, /getExactDocument/)
  assert.doesNotMatch(source, /getDocumentVersionSignedUrl\(doc\.current_version_id\)/)
  assert.doesNotMatch(source, /getTrashedDocumentVersionSignedUrl\(exactDocument\.expectedMatterId, docId, doc\.current_version_id\)/)
})

test('canonical document route retains signed PDF, inspector, Notes, timeline detail, and Trash read-only presentation', () => {
  const source = readFileSync(new URL('./page.tsx', import.meta.url), 'utf8')

  assert.match(source, /getNotes\(\{ documentId: docId \}\)/)
  assert.match(source, /const inspectorIds = documentInspectorIds\(doc\.id, allDocuments\)/)
  assert.match(source, /getDocumentInspectorMetadata\(inspectorIds\)/)
  assert.match(source, /<PdfViewer url=\{signedDocumentUrl\} initialPage=\{sourceLocator\.page \?\? 1\}/)
  assert.match(source, /<TimelineDocumentDetail[\s\S]*inspectorMetadataByDocumentId=\{inspectorMetadata\}[\s\S]*readOnly=\{isTrashReadOnly\}/)
  assert.match(source, /<TrashReadOnlyStrip context=\{exactDocument\.context\}/)
})
