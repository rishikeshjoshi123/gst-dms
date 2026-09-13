import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { linkedDocumentDate, linkedDocumentIdentity, selectedDocumentIdentity } from '@/lib/documents/document-inspector-identity'
import { canonicalDocumentPath } from '@/lib/canonical-document-route'

test('Move or copy launcher preserves historical and read-only gates', () => {
  const source = readFileSync(new URL('./TimelineDocumentDetail.tsx', import.meta.url), 'utf8')
  assert.match(source, /!readOnly && !displayedSource\?\.historical && <Button[^]*?Move or copy/)
  assert.match(source, /!readOnly && !displayedSource\?\.historical && <ReassignDocumentDialog/)
})

test('uses effective reference for selected inspector identity and never revives a cleared reference', () => {
  const document = {
    display_title: 'Neutral storage title.pdf',
    storage_path: 'documents/neutral-storage-title.pdf',
  }

  assert.equal(
    selectedDocumentIdentity(document, { state: 'available', referenceNumber: 'Corrected reference' }),
    'Corrected reference',
  )
  assert.equal(
    selectedDocumentIdentity(document, { state: 'available', referenceNumber: null }),
    'Neutral storage title.pdf',
  )
  assert.equal(
    selectedDocumentIdentity(document, { state: 'unavailable', referenceNumber: 'must not render' }),
    'Neutral storage title.pdf',
  )
})

test('renders linked rows from effective reference and date, with neutral fallbacks after clearing', () => {
  const linkedDocument = {
    display_title: 'Linked neutral title.pdf',
    storage_path: 'documents/linked-neutral-title.pdf',
    created_at: '2026-03-05T00:00:00.000Z',
  }

  assert.equal(
    linkedDocumentIdentity(linkedDocument, { state: 'available', referenceNumber: 'Corrected linked reference' }),
    'Corrected linked reference',
  )
  assert.equal(
    linkedDocumentDate(linkedDocument, { state: 'available', documentDate: '2026-08-30' }),
    '2026-08-30',
  )
  assert.equal(
    linkedDocumentIdentity(linkedDocument, { state: 'available', referenceNumber: null }),
    'Linked neutral title.pdf',
  )
  assert.equal(
    linkedDocumentDate(linkedDocument, { state: 'available', documentDate: null }),
    '2026-03-05',
  )
})

test('uses a guarded financial-year correction and decimal keyboard input', () => {
  const source = readFileSync(new URL('./TimelineDocumentDetail.tsx', import.meta.url), 'utf8')

  assert.match(source, /correction\('document\.financial_year'\)/)
  assert.match(source, /financialYearNeedsReview/)
  assert.match(source, /inputMode=\{type === 'decimal' \? 'decimal' : undefined\}/)
})

test('keeps active document links canonical and binds Trash links to each document matter', () => {
  const source = readFileSync(new URL('./TimelineDocumentDetail.tsx', import.meta.url), 'utf8')

  assert.match(source, /const viewUrl = canonicalDocumentPath\(doc\.id, \{[\s\S]*readOnly \? \{ matterId: doc\.matter_id \} : \{\}/)
  assert.match(source, /canonicalDocumentPath\(ldoc\.id, readOnly \? \{ matterId: ldoc\.matter_id \} : \{\}\)/)
  assert.equal(canonicalDocumentPath('document-id'), '/documents/document-id')
  assert.equal(
    canonicalDocumentPath('document-id', { matterId: 'trash-matter-id' }),
    '/documents/document-id?matterId=trash-matter-id',
  )
})
