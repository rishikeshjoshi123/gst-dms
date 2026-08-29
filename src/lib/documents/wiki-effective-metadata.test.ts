import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { formatMatterWikiEffectiveContext } from './wiki-effective-metadata-shape'
import type { Database } from '@/lib/supabase/database.types'

type Row = Database['public']['Functions']['read_current_document_effective_metadata']['Returns'][number]

const documentId = '00000000-0000-4000-8000-000000000001'
const forgedDocumentId = '00000000-0000-4000-8000-000000000099'
const versionId = '00000000-0000-4000-8000-000000000002'

function row(overrides: Partial<Row> = {}): Row {
  return {
    document_id: documentId,
    document_version_id: versionId,
    semantic_candidate_key: 'document.reference_number',
    field_path: 'document.reference_number',
    value_type: 'text',
    normalized_value: 'SCN/ORIGINAL',
    resolution: 'automatic',
    computed_at: '2026-08-30T00:00:00.000Z',
    ...overrides,
  }
}

test('formats only corrected valid effective fields in stable document and summary order', () => {
  const context = formatMatterWikiEffectiveContext([{ id: documentId, summary: 'Existing summary first.' }], [
    row({ normalized_value: 'SCN/CORRECTED', resolution: 'corrected' }),
    row({ semantic_candidate_key: 'legal_reference:0', field_path: 'legal_reference.provision_number', value_type: 'code', normalized_value: 'Section 74' }),
    row({ semantic_candidate_key: 'deadline:0', field_path: 'deadline.due_date', value_type: 'date', normalized_value: '2026-12-31' }),
    row({ semantic_candidate_key: 'amount:tax', field_path: 'financial.tax', value_type: 'decimal', normalized_value: '1200.50' }),
  ])

  assert.equal(context, `Document [ID: ${documentId}]:
Summary: Existing summary first.
Effective metadata:
- Reference number: SCN/CORRECTED
- Tax: 1200.50
- Legal references: Section 74
- Deadlines: 2026-12-31`)
})

test('omits cleared, rejected, malformed, wrong-type, duplicate, forged, and mixed-version projection values', () => {
  const context = formatMatterWikiEffectiveContext([{ id: documentId, summary: null }], [
    row({ normalized_value: null, resolution: 'cleared' }),
    row({ semantic_candidate_key: 'reference:rejected', normalized_value: 'REJECTED', resolution: 'rejected' }),
    row({ semantic_candidate_key: 'amount:tax', field_path: 'financial.tax', value_type: 'decimal', normalized_value: '1200.50' }),
    row({ semantic_candidate_key: 'amount:tax', field_path: 'financial.tax', value_type: 'text', normalized_value: '1200.50' }),
    row({ semantic_candidate_key: 'deadline:0', field_path: 'deadline.due_date', value_type: 'date', normalized_value: 'not-a-date' }),
    row({ semantic_candidate_key: 'legal_reference:0', field_path: 'legal_reference.provision_number', value_type: 'code', normalized_value: 'Section 74' }),
    row({ semantic_candidate_key: 'legal_reference:0', field_path: 'legal_reference.provision_number', value_type: 'code', normalized_value: 'Section 75' }),
    row({ document_id: forgedDocumentId, normalized_value: 'FORGED CROSS-TENANT VALUE' }),
  ])
  assert.equal(context, `Document [ID: ${documentId}]:
Summary: N/A
Effective metadata: No authorised effective metadata available.`)

  const mixedVersionContext = formatMatterWikiEffectiveContext([{ id: documentId, summary: null }], [
    row(),
    row({ semantic_candidate_key: 'document.type', field_path: 'document.type', value_type: 'code', normalized_value: 'SCN', document_version_id: '00000000-0000-4000-8000-000000000003' }),
  ])
  assert.match(mixedVersionContext, /No authorised effective metadata available/)
  assert.doesNotMatch(mixedVersionContext, /SCN\/ORIGINAL|SCN/)
})

test('keeps generation context deliberate when effective metadata is empty', () => {
  const context = formatMatterWikiEffectiveContext([{ id: documentId, summary: 'Kept non-AI summary.' }], [])
  assert.equal(context, `Document [ID: ${documentId}]:
Summary: Kept non-AI summary.
Effective metadata: No authorised effective metadata available.`)
})

test('suppresses a scalar when its semantic key is duplicated by a malformed row', () => {
  const context = formatMatterWikiEffectiveContext([{ id: documentId, summary: null }], [
    row({ field_path: 'financial.tax', semantic_candidate_key: 'amount:tax', value_type: 'decimal', normalized_value: '1200.50' }),
    row({ field_path: 'financial.tax', semantic_candidate_key: 'amount:tax', value_type: 'text', normalized_value: 'not-a-decimal' }),
  ])

  assert.match(context, /No authorised effective metadata available/)
  assert.doesNotMatch(context, /1200\.50/)
})

test('keeps the live worker service-only, bounded, and free of legacy metadata', () => {
  const worker = readFileSync(new URL('../../trigger/jobs.ts', import.meta.url), 'utf8')
  const reader = readFileSync(new URL('./wiki-effective-metadata.ts', import.meta.url), 'utf8')

  const workerSlice = worker.slice(worker.indexOf("id: 'generate-matter-wiki'"))
  assert.match(reader, /import 'server-only'/)
  assert.match(reader, /\.rpc\('read_current_document_effective_metadata'/)
  assert.doesNotMatch(reader, /\.from\('document_effective_metadata'\)/)
  assert.match(workerSlice, /\.eq\('matter_id', matterId\)[\s\S]*\.eq\('org_id', orgId\)[\s\S]*\.is\('deleted_at', null\)[\s\S]*\.eq\('record_state', 'active'\)/)
  assert.match(workerSlice, /readCurrentDocumentWikiMetadata\(supabase, orgId, docs\.map/)
  assert.match(workerSlice, /formatMatterWikiEffectiveContext\(docs, effectiveMetadata\)/)
  assert.doesNotMatch(workerSlice, /raw_metadata|JSON\.stringify\(d\./)
})
