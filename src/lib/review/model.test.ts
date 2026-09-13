import assert from 'node:assert/strict'
import test from 'node:test'
import { parseReviewFilters, reviewResolution, reviewValueLabel, taxPeriodComparison } from './model'

test('Review URL parsing allowlists filters, bounds search/page and rejects repeated authority', () => {
  assert.deepEqual(parseReviewFilters({ status: ['closed', 'all'], type: 'deadline', priority: 'critical', page: '-1', item: 'not-an-id', tab: 'history' }), {
    status: 'needs_review', type: 'all', priority: 'all', search: '', page: 1, item: undefined, tab: 'evidence',
  })
  const result = parseReviewFilters({ status: 'closed', priority: 'high', search: 'a'.repeat(201), page: '999999', tab: 'decision', item: '153e0000-0000-0000-0000-000000000001' })
  assert.equal(result.search.length, 200)
  assert.equal(result.page, 100000)
  assert.equal(result.item, '153e0000-0000-0000-0000-000000000001')
})
test('typed decision rejects arbitrary domain changes, dismiss and mismatched candidate shape', () => {
  const base = { itemId: '153e0000-0000-0000-0000-000000000001', revision: 1, action: 'request_clarification', candidateId: null, reason: 'Explain the source difference', idempotencyKey: '15390000-0000-0000-0000-000000000001' }
  assert.equal(reviewResolution.safeParse(base).success, true)
  for (const invalid of [{ ...base, action: 'dismiss' }, { ...base, reason: '' }, { ...base, reason: 'a'.repeat(501) }, { ...base, reason: 'line\nbreak' }, { ...base, action: 'select_candidate' }, { ...base, orgId: 'arbitrary' }, { ...base, revision: 0 }, { ...base, candidateId: base.itemId }]) assert.equal(reviewResolution.safeParse(invalid).success, false)
})
test('display preserves source observations and labels derived tax-period comparisons separately', () => {
  assert.equal(reviewValueLabel({ display: 'January 2025', normalized_value: 'hidden' }), 'January 2025')
  assert.equal(reviewValueLabel({ random: 'untrusted' }), 'Source observation')
  assert.equal(taxPeriodComparison({ conflict: false }), null)
  assert.deepEqual(taxPeriodComparison({ conflict: true, printed_financial_years: ['2023-24'], derived_financial_years: ['2024-25'] }), { printed: '2023-24', derived: '2024-25' })
})
