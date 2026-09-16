import assert from 'node:assert/strict'
import test from 'node:test'
import { ambiguousPlacementResolution, deadlineReviewResolution, extractionReviewResolution, parseReviewFilters, possibleDuplicateResolution, processingRecoveryResolution, reviewAction, reviewValueLabel, taxPeriodComparison } from './model'

test('possible duplicate names an exact subset or all-distinct, never an implicit group equivalence',()=>{
  const ids=['153e0000-0000-0000-0000-000000000001','153e0000-0000-0000-0000-000000000002']
  const base={itemId:ids[0],revision:1,action:'possible_same_document',selectedDocumentIds:ids,
    reason:'Both exact sources need a further governed identity investigation',idempotencyKey:'15390000-0000-0000-0000-000000000001'}
  assert.equal(possibleDuplicateResolution.safeParse(base).success,true)
  assert.equal(possibleDuplicateResolution.safeParse({...base,action:'distinct_documents',selectedDocumentIds:[]}).success,true)
  for(const invalid of [{...base,selectedDocumentIds:[]},{...base,selectedDocumentIds:[ids[0]]},
    {...base,selectedDocumentIds:[ids[0],ids[0]]},{...base,action:'distinct_documents'},
    {...base,selectedDocumentIds:[...ids,...ids,...ids,...ids,...ids]},{...base,reason:'line\nbreak'}])
    assert.equal(possibleDuplicateResolution.safeParse(invalid).success,false)
})

test('Review URL parsing allowlists filters, bounds search/page and rejects repeated authority', () => {
  assert.deepEqual(parseReviewFilters({ status: ['closed', 'all'], type: 'deadline', priority: 'critical', page: '-1', item: 'not-an-id', tab: 'history' }), {
    status: 'needs_review', type: 'all', priority: 'all', search: '', page: 1, item: undefined, tab: 'evidence',
  })
  const result = parseReviewFilters({ status: 'closed', priority: 'high', search: 'a'.repeat(201), page: '999999', tab: 'decision', item: '153e0000-0000-0000-0000-000000000001' })
  assert.equal(result.search.length, 200)
  assert.equal(result.page, 100000)
  assert.equal(result.item, '153e0000-0000-0000-0000-000000000001')
})
test('ambiguous placement exposes only one typed destination decision', () => {
  const base = { itemId: '153e0000-0000-0000-0000-000000000001', revision: 1, action: 'select_destination', placementCandidateId: '162e0000-0000-0000-0000-000000000001', reason: 'Exact referenced order supports this proceeding', idempotencyKey: '16290000-0000-0000-0000-000000000001' }
  assert.equal(ambiguousPlacementResolution.safeParse(base).success, true)
  for (const invalid of [{ ...base, action: 'dismiss' }, { ...base, matterId: base.placementCandidateId }, { ...base, placementCandidateId: 'forged' }, { ...base, reason: '' }, { ...base, reason: 'line\nbreak' }, { ...base, revision: 0 }]) assert.equal(ambiguousPlacementResolution.safeParse(invalid).success, false)
  assert.equal(parseReviewFilters({ type: 'ambiguous_placement' }).type, 'ambiguous_placement')
})
test('typed decision rejects arbitrary domain changes, dismiss and mismatched candidate shape', () => {
  const base = { itemId: '153e0000-0000-0000-0000-000000000001', revision: 1, action: 'request_clarification', candidateId: null, reason: 'Explain the source difference', idempotencyKey: '15390000-0000-0000-0000-000000000001' }
  assert.equal(extractionReviewResolution.safeParse(base).success, true)
  for (const invalid of [{ ...base, action: 'dismiss' }, { ...base, reason: '' }, { ...base, reason: 'a'.repeat(501) }, { ...base, reason: 'line\nbreak' }, { ...base, action: 'select_candidate' }, { ...base, orgId: 'arbitrary' }, { ...base, revision: 0 }, { ...base, candidateId: base.itemId }]) assert.equal(extractionReviewResolution.safeParse(invalid).success, false)
})
test('manual recovery requires a bounded typed metadata set and cannot request extraction retry', () => {
  const base = { itemId: '153e0000-0000-0000-0000-000000000001', revision: 1, action: 'continue_manual', reason: 'Verified against the PDF', idempotencyKey: '15390000-0000-0000-0000-000000000001', metadata: { doc_type: 'SCN', reference_number: 'SCN/42', document_date: '2026-09-15', direction: 'incoming', issued_by: 'GST Authority' } }
  assert.equal(processingRecoveryResolution.safeParse(base).success, true)
  for (const invalid of [{ ...base, action: 'retry_extraction' }, { ...base, metadata: { ...base.metadata, doc_type: 'UNKNOWN' } }, { ...base, metadata: { ...base.metadata, document_date: '2026-02-30' } }, { ...base, metadata: { ...base.metadata, reference_number: '' } }, { ...base, metadata: { ...base.metadata, raw_provider_response: '{}' } }]) assert.equal(processingRecoveryResolution.safeParse(invalid).success, false)
})
test('date Review has only four typed decisions and a real corrected calendar date', () => {
  const base={itemId:'153e0000-0000-0000-0000-000000000001',revision:1,
    action:'verify',correctedDueDate:null,reason:'Verified against page two',
    idempotencyKey:'15390000-0000-0000-0000-000000000001'}
  assert.equal(deadlineReviewResolution.safeParse(base).success,true)
  assert.equal(deadlineReviewResolution.safeParse({...base,action:'correct',correctedDueDate:'2026-10-17'}).success,true)
  for(const invalid of [{...base,action:'dismiss'},{...base,correctedDueDate:'2026-10-17'},
    {...base,action:'correct',correctedDueDate:null},{...base,action:'correct',correctedDueDate:'2026-02-30'},
    {...base,reason:'x'},{...base,raw_metadata:{due_date:'2026-10-17'}}])
    assert.equal(deadlineReviewResolution.safeParse(invalid).success,false)
  assert.equal(parseReviewFilters({type:'deadline_verification'}).type,'deadline_verification')
  assert.equal(reviewAction.safeParse('correct_deadline').success,true)
  assert.equal(reviewAction.safeParse('correct').success,true)
})
test('display preserves source observations and labels derived tax-period comparisons separately', () => {
  assert.equal(reviewValueLabel({ display: 'January 2025', normalized_value: 'hidden' }), 'January 2025')
  assert.equal(reviewValueLabel({ random: 'untrusted' }), 'Source observation')
  assert.equal(taxPeriodComparison({ conflict: false }), null)
  assert.deepEqual(taxPeriodComparison({ conflict: true, printed_financial_years: ['2023-24'], derived_financial_years: ['2024-25'] }), { printed: '2023-24', derived: '2024-25' })
})
