import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { shapeDocumentInspectorMetadata } from './inspector-metadata-shape'
import type { Database } from '@/lib/supabase/database.types'

type Row = Database['public']['Functions']['read_current_document_inspector_projection']['Returns'][number]

const documentId = '00000000-0000-4000-8000-000000000001'
const versionId = '00000000-0000-4000-8000-000000000002'

function row(overrides: Partial<Row> = {}): Row {
  return {
    document_id: documentId,
    document_version_id: versionId,
    document_field_candidate_id: '00000000-0000-4000-8000-000000000010',
    semantic_candidate_key: 'document.reference_number',
    field_path: 'document.reference_number',
    value_type: 'text',
    normalized_value: 'SCN/ORIGINAL',
    resolution: 'automatic',
    computed_at: '2026-08-29T00:00:00.000Z',
    ...overrides,
  }
}

test('uses corrected current-version values and preserves repeated financial years', () => {
  const metadata = shapeDocumentInspectorMetadata([documentId], [
    row({ normalized_value: 'SCN/CORRECTED', resolution: 'corrected' }),
    row({ document_field_candidate_id: '00000000-0000-4000-8000-000000000011', semantic_candidate_key: 'financial_year:0', field_path: 'document.financial_year', value_type: 'code', normalized_value: '2023-24' }),
    row({ document_field_candidate_id: '00000000-0000-4000-8000-000000000012', semantic_candidate_key: 'financial_year:1', field_path: 'document.financial_year', value_type: 'code', normalized_value: '2024-25' }),
    row({ semantic_candidate_key: 'amount:tax', field_path: 'financial.tax', value_type: 'decimal', normalized_value: '1200.50', resolution: 'corrected' }),
    row({ semantic_candidate_key: 'amount:interest', field_path: 'financial.interest', value_type: 'decimal', normalized_value: null, resolution: 'cleared' }),
    row({ semantic_candidate_key: 'amount:penalty', field_path: 'financial.penalty', value_type: 'decimal', normalized_value: null, resolution: 'rejected' }),
  ])[documentId]

  assert.deepEqual(metadata, {
    state: 'available', documentVersionId: versionId, docType: null,
    referenceNumber: 'SCN/CORRECTED', documentDate: null, clientName: null,
    gstin: null, financialYears: ['2023-24', '2024-25'], tax: '1200.50', interest: null,
    penalty: null, totalDemand: null, issuedBy: null, direction: null,
    fieldCandidates: {
      'document.reference_number': { id: '00000000-0000-4000-8000-000000000010', valueType: 'text' },
      'financial.tax': { id: '00000000-0000-4000-8000-000000000010', valueType: 'decimal' },
      'financial.interest': { id: '00000000-0000-4000-8000-000000000010', valueType: 'decimal' },
      'financial.penalty': { id: '00000000-0000-4000-8000-000000000010', valueType: 'decimal' },
    },
  })
})

test('never uses cleared, rejected, ambiguous, forged, or mismatched-version values', () => {
  const forgedId = '00000000-0000-4000-8000-000000000099'
  const metadata = shapeDocumentInspectorMetadata([documentId], [
    row({ normalized_value: null, resolution: 'cleared' }),
    row({ semantic_candidate_key: 'document.reference_number.rejected', normalized_value: null, resolution: 'rejected' }),
    row({ semantic_candidate_key: 'document.reference_number.other', normalized_value: 'SECOND VALUE' }),
    row({ document_id: forgedId, normalized_value: 'FORGED CROSS-TENANT VALUE' }),
    row({ document_version_id: '00000000-0000-4000-8000-000000000003', normalized_value: 'STALE VERSION VALUE' }),
  ])[documentId]

  assert.equal(metadata.state, 'unavailable')
  assert.equal(metadata.referenceNumber, null)
})

test('returns an intentional unavailable state when the projection has no row', () => {
  assert.deepEqual(shapeDocumentInspectorMetadata([documentId], [])[documentId], {
    state: 'unavailable', documentVersionId: null, docType: null, referenceNumber: null,
    documentDate: null, clientName: null, gstin: null, financialYears: [], tax: null,
    interest: null, penalty: null, totalDemand: null, issuedBy: null, direction: null, fieldCandidates: {},
  })
})

test('keeps a cleared current candidate available for correction without displaying its value', () => {
  const metadata = shapeDocumentInspectorMetadata([documentId], [
    row({ field_path: 'financial.total_demand', value_type: 'decimal', normalized_value: null, resolution: 'cleared' }),
  ])[documentId]
  assert.equal(metadata.state, 'available')
  assert.equal(metadata.totalDemand, null)
  assert.deepEqual(metadata.fieldCandidates['financial.total_demand'], {
    id: '00000000-0000-4000-8000-000000000010', valueType: 'decimal',
  })
})

test('keeps the protected projection reader on the server and wires both live inspector callers', () => {
  const readerSource = readFileSync(new URL('./inspector-effective-metadata.ts', import.meta.url), 'utf8')
  const detailSource = readFileSync(new URL('../../components/matters/TimelineDocumentDetail.tsx', import.meta.url), 'utf8')
  const documentPageSource = readFileSync(new URL('../../app/(app)/matters/[id]/documents/[docId]/page.tsx', import.meta.url), 'utf8')
  const matterPageSource = readFileSync(new URL('../../app/(app)/matters/[id]/page.tsx', import.meta.url), 'utf8')

  assert.match(readerSource, /import 'server-only'/)
  assert.match(readerSource, /createServiceClient\(\)\.rpc\('read_current_document_inspector_projection'/)
  assert.match(readerSource, /requester[\s\S]*\.from\('documents'\)/)
  assert.doesNotMatch(detailSource, /raw_metadata|extracted_amounts/)
  assert.match(documentPageSource, /const inspectorIds = documentInspectorIds\(doc\.id, allDocuments\)/)
  assert.match(documentPageSource, /getDocumentInspectorMetadata\(inspectorIds\)/)
  assert.match(documentPageSource, /inspectorMetadataByDocumentId=\{inspectorMetadata\}/)
  assert.match(matterPageSource, /getDocumentInspectorMetadata\(documentIds\)/)
  assert.match(detailSource, /inspectorMetadata\.referenceNumber/)
})

test('financial-year correction preserves a single cleared or corrected candidate and rejects multiple candidates', () => {
  const corrected = shapeDocumentInspectorMetadata([documentId], [
    row({ field_path: 'document.financial_year', semantic_candidate_key: 'financial_year:0', value_type: 'code', normalized_value: '2024-25', resolution: 'corrected' }),
  ])[documentId]
  assert.deepEqual(corrected.financialYears, ['2024-25'])
  assert.deepEqual(corrected.fieldCandidates['document.financial_year'], {
    id: '00000000-0000-4000-8000-000000000010', valueType: 'code',
  })

  const cleared = shapeDocumentInspectorMetadata([documentId], [
    row({ field_path: 'document.financial_year', semantic_candidate_key: 'financial_year:0', value_type: 'code', normalized_value: null, resolution: 'cleared' }),
  ])[documentId]
  assert.deepEqual(cleared.financialYears, [])
  assert.deepEqual(cleared.fieldCandidates['document.financial_year'], {
    id: '00000000-0000-4000-8000-000000000010', valueType: 'code',
  })

  const multiple = shapeDocumentInspectorMetadata([documentId], [
    row({ document_field_candidate_id: '00000000-0000-4000-8000-000000000011', field_path: 'document.financial_year', semantic_candidate_key: 'financial_year:0', value_type: 'code', normalized_value: '2023-24' }),
    row({ document_field_candidate_id: '00000000-0000-4000-8000-000000000012', field_path: 'document.financial_year', semantic_candidate_key: 'financial_year:1', value_type: 'code', normalized_value: '2024-25' }),
  ])[documentId]
  assert.deepEqual(multiple.financialYears, ['2023-24', '2024-25'])
  assert.equal(multiple.fieldCandidates['document.financial_year'], undefined)
})
