import assert from 'node:assert/strict'
import { produceAmbiguousIntakePlacementReview } from '../../src/lib/review/placement-orchestration'

const result = await produceAmbiguousIntakePlacementReview({
  intakeId: '16470000-0000-0000-0000-000000000001',
  sourceRevision: 'trusted-placement-browser-v1',
  candidates: [
    { matter_id: '164d0000-0000-0000-0000-000000000001', evidence: [{ kind: 'verified_client_identifier', source_page_number: 1 }] },
    { matter_id: '164d0000-0000-0000-0000-000000000002', evidence: [{ kind: 'referenced_document_exact', source_page_number: 2 }] },
  ],
})
assert.equal(result?.code, 'ok')
assert.match(result?.review_item_id ?? '', /^[0-9a-f-]{36}$/)
const unavailable = await produceAmbiguousIntakePlacementReview({
  intakeId: '16470000-0000-0000-0000-000000000002',
  sourceRevision: 'trusted-placement-browser-v1',
  candidates: [
    { matter_id: '164d0000-0000-0000-0000-000000000001', evidence: [{ kind: 'verified_client_identifier', source_page_number: 1 }] },
    { matter_id: '164d0000-0000-0000-0000-000000000002', evidence: [{ kind: 'referenced_document_exact', source_page_number: 2 }] },
  ],
})
assert.equal(unavailable?.code, 'ok')
console.log('Production trusted-placement service boundary created the browser Review fixture.')
