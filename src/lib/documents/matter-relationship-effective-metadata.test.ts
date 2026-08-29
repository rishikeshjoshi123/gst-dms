import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { shapeMatterRelationshipMetadata } from './matter-relationship-metadata-shape'

const documentId = '00000000-0000-4000-8000-000000000001'
const versionId = '00000000-0000-4000-8000-000000000002'

function row(overrides: Record<string, unknown> = {}) {
  return {
    document_id: documentId,
    document_version_id: versionId,
    doc_type: 'SCN',
    reference_number: 'SCN/CORRECTED',
    referenced_document_numbers: ['OIO/CORRECTED', 'OIO/CORRECTED', 'APL/22'],
    ...overrides,
  }
}

test('shapes corrected relationship references, keeps multiple references, and never invents a fallback', () => {
  assert.deepEqual(shapeMatterRelationshipMetadata([row()]), [{
    documentId,
    documentVersionId: versionId,
    docType: 'SCN',
    referenceNumber: 'SCN/CORRECTED',
    referencedDocumentNumbers: ['OIO/CORRECTED', 'APL/22'],
  }])

  assert.deepEqual(shapeMatterRelationshipMetadata([row({
    doc_type: null,
    reference_number: null,
    referenced_document_numbers: [],
  })])[0], {
    documentId,
    documentVersionId: versionId,
    docType: null,
    referenceNumber: null,
    referencedDocumentNumbers: [],
  })
})

test('keeps an empty effective reference list empty when extraction was absent or rejected before candidate creation', () => {
  for (const fieldCount of [0, 1]) {
    const metadata = shapeMatterRelationshipMetadata([row({
      referenced_document_numbers: [],
      referenced_document_field_count: fieldCount,
    })])
    assert.deepEqual(metadata[0].referencedDocumentNumbers, [])
  }
})

test('ignores duplicate/forged projection rows instead of mixing versions or values', () => {
  const result = shapeMatterRelationshipMetadata([
    row(),
    row({ document_version_id: '00000000-0000-4000-8000-000000000003', doc_type: 'FORGED' }),
  ])
  assert.equal(result.length, 1)
  assert.equal(result[0].documentVersionId, versionId)
  assert.equal(result[0].docType, 'SCN')
})

test('keeps the reader server-only, authorises the matter before its service RPC, and leaves re-evaluation free of raw metadata', () => {
  const reader = readFileSync(new URL('./matter-relationship-effective-metadata.ts', import.meta.url), 'utf8')
  const chaining = readFileSync(new URL('../actions/chaining.ts', import.meta.url), 'utf8')

  assert.match(reader, /import 'server-only'/)
  assert.match(reader, /requester[\s\S]*\.from\('matters'\)/)
  assert.match(reader, /createServiceClient\(\)\.rpc\('read_current_matter_relationship_projection'/)
  assert.doesNotMatch(reader, /\.raw_metadata/)
  const reevaluation = chaining.slice(chaining.indexOf('export async function reevaluateMatterLinks'))
  assert.match(reevaluation, /getCurrentMatterRelationshipMetadata\(matterId\)/)
  assert.doesNotMatch(reevaluation, /\.raw_metadata/)
  assert.doesNotMatch(reevaluation, /progression_inference|progressionTargetType/)
})
