import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { relationshipDocumentPresentation } from '@/lib/documents/document-inspector-identity'

const document = {
  id: 'document-id-1',
  display_title: 'Notice attachment.pdf',
  storage_path: 'org/matter/notice-storage-name.pdf',
}

test('relationship presentation uses corrected effective metadata for type and reference', () => {
  assert.deepEqual(relationshipDocumentPresentation(document, {
    state: 'available',
    docType: 'OIO',
    referenceNumber: 'OIO/CORRECTED/42',
  }), {
    documentType: 'OIO',
    reference: 'OIO/CORRECTED/42',
  })
})

test('relationship presentation never revives cleared, rejected, missing, or stale legacy metadata', () => {
  const cleared = relationshipDocumentPresentation(document, {
    state: 'available',
    docType: null,
    referenceNumber: null,
  })
  const missing = relationshipDocumentPresentation({
    id: 'document-id-2',
    storage_path: 'org/matter/storage-only.pdf',
  }, undefined)

  assert.deepEqual(cleared, {
    documentType: 'Type unavailable',
    reference: 'Notice attachment.pdf',
  })
  assert.deepEqual(missing, {
    documentType: 'Type unavailable',
    reference: 'storage-only.pdf',
  })
})

test('relationship dialogs receive TimelineGraph current metadata entries and contain no legacy metadata reads', () => {
  const graphSource = readFileSync(new URL('./TimelineGraph.tsx', import.meta.url), 'utf8')
  const creationSource = readFileSync(new URL('./LinkCreationDialog.tsx', import.meta.url), 'utf8')
  const deletionSource = readFileSync(new URL('./LinkDeletionDialog.tsx', import.meta.url), 'utf8')

  assert.match(graphSource, /parentEffectiveMetadata=\{linkDialogState\.sourceDoc \? inspectorMetadataByDocumentId\[linkDialogState\.sourceDoc\.id\] : undefined\}/)
  assert.match(graphSource, /childEffectiveMetadata=\{linkDialogState\.targetDoc \? inspectorMetadataByDocumentId\[linkDialogState\.targetDoc\.id\] : undefined\}/)
  assert.match(graphSource, /sourceEffectiveMetadata=\{deleteDialogState\.sourceDoc \? inspectorMetadataByDocumentId\[deleteDialogState\.sourceDoc\.id\] : undefined\}/)
  assert.match(graphSource, /targetEffectiveMetadata=\{deleteDialogState\.targetDoc \? inspectorMetadataByDocumentId\[deleteDialogState\.targetDoc\.id\] : undefined\}/)

  for (const source of [creationSource, deletionSource]) {
    assert.match(source, /relationshipDocumentPresentation/)
    assert.doesNotMatch(source, /raw_metadata|\.doc_type|\.reference_number/)
  }
})
