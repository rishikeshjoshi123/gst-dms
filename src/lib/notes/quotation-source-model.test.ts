import assert from 'node:assert/strict'
import test from 'node:test'

import { quotationSourcePresentation } from './quotation-source-model'

const locator = {
  document_id: 'document-a',
  document_version_id: '00000000-0000-4000-8000-000000000002',
  page_number: 7,
  excerpt: 'Immutable excerpt',
  version_number: 2,
  is_current: false,
  source_available: true,
}

test('builds an exact immutable version/page action and identifies historical bytes', () => {
  assert.deepEqual(quotationSourcePresentation({ quote: 'legacy copy', page_number: 1, quotation_locator: locator }), {
    kind: 'exact',
    excerpt: 'Immutable excerpt',
    pageNumber: 7,
    versionNumber: 2,
    historical: true,
    href: '/documents/document-a?version=00000000-0000-4000-8000-000000000002&page=7',
  })
})

test('preserves ambiguous legacy excerpts without inventing an exact action', () => {
  assert.deepEqual(quotationSourcePresentation({ quote: 'Legacy excerpt', page_number: 4 }), {
    kind: 'unverified', excerpt: 'Legacy excerpt', href: null, pageNumber: 4,
  })
})

test('preserves an exact excerpt but withholds its action when source is unavailable', () => {
  assert.deepEqual(quotationSourcePresentation({ quotation_locator: { ...locator, source_available: false } }), {
    kind: 'unavailable', excerpt: 'Immutable excerpt', pageNumber: 7, versionNumber: 2,
    historical: true, href: null,
  })
})

test('adds verified Trash lineage without changing immutable version/page identity', () => {
  assert.equal(
    quotationSourcePresentation({ quotation_locator: locator }, { readOnly: true, matterId: 'matter-a' }).href,
    '/documents/document-a?matterId=matter-a&version=00000000-0000-4000-8000-000000000002&page=7',
  )
})
