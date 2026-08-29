import assert from 'node:assert/strict'
import test from 'node:test'
import {
  normalizeGSTIN,
  normalizePAN,
  readCurrentDocumentAssignmentMetadata,
  resolveDocumentAssignment,
} from './assignment'
import type { EffectiveDocumentAssignmentMetadata } from './assignment'

const ORG_ID = '00000000-0000-4000-8000-000000000001'
const CLIENT_ID = '00000000-0000-4000-8000-000000000002'
const MATTER_ID = '00000000-0000-4000-8000-000000000003'

function assignmentMetadata(overrides: Partial<EffectiveDocumentAssignmentMetadata> = {}): EffectiveDocumentAssignmentMetadata {
  return {
    documentId: '00000000-0000-4000-8000-000000000004',
    documentVersionId: '00000000-0000-4000-8000-000000000005',
    gstin: null,
    clientIdentifiers: [],
    clientName: 'Example Private Limited',
    financialYears: ['2024-25'],
    referenceNumber: null,
    referencedDocumentNumbers: [],
    ...overrides,
  }
}

/** Minimal query double for the GSTIN → client → matter path. */
function gstinAssignmentDb() {
  const client = {
    id: CLIENT_ID,
    name: 'Example Private Limited',
    gstin: '27ABCDE1234F1Z5',
    pan: null,
  }
  const matter = { id: MATTER_ID, client_id: CLIENT_ID }

  return {
    from(table: string) {
      const query = {
        select() { return query },
        eq() { return query },
        is() { return query },
        ilike() { return query },
        async maybeSingle() {
          return { data: table === 'clients' ? client : matter, error: null }
        },
      }
      return query
    },
  } as unknown as Parameters<typeof resolveDocumentAssignment>[0]
}

function referenceAssignmentDb(clientGstin: string | null) {
  const client = {
    id: CLIENT_ID,
    name: 'Example Private Limited',
    gstin: clientGstin,
    pan: null,
  }
  const referenceDocument = {
    id: '00000000-0000-4000-8000-000000000004',
    matter_id: MATTER_ID,
    deleted_at: null,
    matters: {
      id: MATTER_ID,
      client_id: CLIENT_ID,
      deleted_at: null,
      clients: { deleted_at: null },
    },
  }

  return {
    from(table: string) {
      const query = {
        select() { return query },
        eq() { return query },
        is() { return query },
        ilike() { return query },
        async maybeSingle() {
          return { data: table === 'clients' ? client : null, error: null }
        },
        then<TResult1 = unknown, TResult2 = never>(
          onfulfilled?: ((value: unknown) => TResult1 | PromiseLike<TResult1>) | null,
          onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
        ) {
          return Promise.resolve({
            data: table === 'documents' ? [referenceDocument] : [],
            error: null,
          }).then(onfulfilled, onrejected)
        },
      }
      return query
    },
  } as unknown as Parameters<typeof resolveDocumentAssignment>[0]
}

function unmatchedClientDb() {
  return {
    from() {
      const query = {
        select() { return query },
        eq() { return query },
        is() { return query },
        ilike() { return query },
        insert() {
          throw new Error('The assignment resolver must not create records')
        },
        async maybeSingle() {
          return { data: null, error: null }
        },
        then<TResult1 = unknown, TResult2 = never>(
          onfulfilled?: ((value: unknown) => TResult1 | PromiseLike<TResult1>) | null,
          onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
        ) {
          return Promise.resolve({ data: [], error: null }).then(onfulfilled, onrejected)
        },
      }
      return query
    },
  } as unknown as Parameters<typeof resolveDocumentAssignment>[0]
}

test('normalizes GSTIN and PAN independently', () => {
  assert.equal(normalizeGSTIN('27abcde1234f1z5'), '27ABCDE1234F1Z5')
  assert.equal(normalizePAN(' abcde-1234-f '), 'ABCDE1234F')
  assert.equal(normalizePAN(null), null)
})

test('reads the bounded current assignment projection with the caller tenant and no raw metadata fallback', async () => {
  let rpcName = ''
  let rpcArgs: Record<string, unknown> | undefined
  const metadata = await readCurrentDocumentAssignmentMetadata({
    async rpc(name: string, args: Record<string, unknown>) {
      rpcName = name
      rpcArgs = args
      return {
        data: [{
          document_id: '00000000-0000-4000-8000-000000000004',
          document_version_id: '00000000-0000-4000-8000-000000000005',
          gstin: '27ABCDE1234F1Z5',
          client_identifiers: ['ABCDE1234F'],
          client_name: 'Corrected Example Private Limited',
          financial_years: ['2024-25'],
          reference_number: null,
          referenced_document_numbers: [],
        }],
        error: null,
      }
    },
  } as unknown as Parameters<typeof readCurrentDocumentAssignmentMetadata>[0], ORG_ID, '00000000-0000-4000-8000-000000000004')

  assert.equal(rpcName, 'read_current_document_assignment_projection')
  assert.deepEqual(rpcArgs, {
    p_org_id: ORG_ID,
    p_document_ids: ['00000000-0000-4000-8000-000000000004'],
  })
  assert.deepEqual(metadata?.clientIdentifiers, ['ABCDE1234F'])
  assert.equal(metadata?.clientName, 'Corrected Example Private Limited')
})

test('treats a missing projection row as terminally unavailable rather than falling back', async () => {
  const metadata = await readCurrentDocumentAssignmentMetadata({
    async rpc() { return { data: [], error: null } },
  } as unknown as Parameters<typeof readCurrentDocumentAssignmentMetadata>[0], ORG_ID, '00000000-0000-4000-8000-000000000004')

  assert.equal(metadata, null)
})

test('auto-assigns a GSTIN-only document when the client has no PAN', async () => {
  const result = await resolveDocumentAssignment(
    gstinAssignmentDb(),
    ORG_ID,
    assignmentMetadata({ gstin: '27abcde1234f1z5' }),
  )

  assert.deepEqual(result, {
    type: 'auto_assign',
    assignments: [{
      matterId: MATTER_ID,
      clientId: CLIENT_ID,
      confidence: 1,
      method: 'client_fy_match',
      crossVerified: true,
    }],
  })
})

test('auto-assigns an exact reference with no GSTIN or PAN as unreviewed', async () => {
  const result = await resolveDocumentAssignment(
    referenceAssignmentDb(null),
    ORG_ID,
    assignmentMetadata({ referencedDocumentNumbers: ['OIO/2024/123'] }),
  )

  assert.deepEqual(result, {
    type: 'auto_assign',
    assignments: [{
      matterId: MATTER_ID,
      clientId: CLIENT_ID,
      confidence: 1,
      method: 'reference_match',
      crossVerified: null,
    }],
  })
})

test('blocks an exact reference when its GSTIN conflicts with the target client', async () => {
  const result = await resolveDocumentAssignment(
    referenceAssignmentDb('27ABCDE1234F1Z5'),
    ORG_ID,
    assignmentMetadata({
      gstin: '29ABCDE1234F1Z5',
      referencedDocumentNumbers: ['OIO/2024/123'],
    }),
  )

  assert.equal(result.type, 'ready_to_assign')
  assert.match(result.reason, /GSTIN\/PAN mismatch/)
  assert.deepEqual(result.suggestions, [{
    matterId: MATTER_ID,
    clientId: CLIENT_ID,
    reason: 'Reference matched but GSTIN/PAN mismatch with client "Example Private Limited" — possible misfiling. Please verify.',
  }])
})

test('requires manual assignment when multiple financial years are extracted', async () => {
  const noDatabaseAccess = {
    from() {
      throw new Error('Multi-FY documents must not query or mutate assignment data')
    },
  } as unknown as Parameters<typeof resolveDocumentAssignment>[0]

  const result = await resolveDocumentAssignment(
    noDatabaseAccess,
    ORG_ID,
    assignmentMetadata({ financialYears: ['FY 2023-24', '2024-2025'] }),
  )

  assert.deepEqual(result, {
    type: 'ready_to_assign',
    reason: 'Document spans multiple financial years (2023-24, 2024-25). Please assign manually.',
    suggestions: [],
  })
})

test('proposes, but never creates, a new client or matter from AI metadata', async () => {
  const result = await resolveDocumentAssignment(
    unmatchedClientDb(),
    ORG_ID,
    assignmentMetadata({ gstin: '27ABCDE1234F1Z5' }),
  )

  assert.deepEqual(result, {
    type: 'ready_to_assign',
    reason: 'No existing client matched. Review and confirm creation for Example Private Limited (2024-25).',
    suggestions: [],
  })
})
