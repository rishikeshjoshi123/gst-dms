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

test('standalone route passes the expanded projection map to linked inspector rows', () => {
  const source = readFileSync(new URL('./page.tsx', import.meta.url), 'utf8')

  assert.match(source, /getDocumentInspectorMetadata\(documentInspectorIds\(doc\.id, allDocuments\)\)/)
  assert.match(source, /inspectorMetadataByDocumentId=\{inspectorMetadata\}/)
})
