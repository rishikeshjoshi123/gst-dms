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

/** Minimal query double for the GSTIN → client → manual Matter suggestions path. */
function gstinAssignmentDb(
  matters = [{
    id: MATTER_ID,
    client_id: CLIENT_ID,
    title: 'Example proceeding',
    financial_year: '2024-25',
  }],
  onMatterLimit?: (limit: number) => void,
  onMatterFilter?: (column: string, value: unknown) => void,
) {
  const client = {
    id: CLIENT_ID,
    name: 'Example Private Limited',
    gstin: '27ABCDE1234F1Z5',
    pan: null,
  }
  return {
    from(table: string) {
      const query = {
        select() { return query },
        eq(column: string, value: unknown) {
          if (table === 'matters') onMatterFilter?.(column, value)
          return query
        },
        in() { return query },
        is() { return query },
        ilike() { return query },
        order() { return query },
        limit(value: number) {
          if (table === 'matters') onMatterLimit?.(value)
          return query
        },
        async maybeSingle() {
          if (table === 'matters') throw new Error('Client/FY lookup must not use maybeSingle')
          return { data: table === 'clients' ? client : null, error: null }
        },
        then<TResult1 = unknown, TResult2 = never>(
          onfulfilled?: ((value: unknown) => TResult1 | PromiseLike<TResult1>) | null,
          onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
        ) {
          return Promise.resolve({ data: table === 'matters' ? matters : [], error: null })
            .then(onfulfilled, onrejected)
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

test('offers a GSTIN and financial-year match for manual confirmation without auto-assignment', async () => {
  const result = await resolveDocumentAssignment(
    gstinAssignmentDb(),
    ORG_ID,
    assignmentMetadata({ gstin: '27abcde1234f1z5' }),
  )

  assert.deepEqual(result, {
    type: 'ready_to_assign',
    reason: 'Client and financial-year evidence found one possible Matter. Confirm the destination manually.',
    suggestions: [{
      matterId: MATTER_ID,
      clientId: CLIENT_ID,
      reason: 'Possible destination for 2024-25: Example proceeding',
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

test('offers every bounded same-client candidate across multiple extracted financial years', async () => {
  let matterLimit = 0
  const matterFilters = new Map<string, unknown>()
  const result = await resolveDocumentAssignment(
    gstinAssignmentDb([
      { id: MATTER_ID, client_id: CLIENT_ID, title: 'First proceeding', financial_year: '2024-25' },
      { id: '00000000-0000-4000-8000-000000000006', client_id: CLIENT_ID, title: 'Parallel proceeding', financial_year: '2024-25' },
      { id: '00000000-0000-4000-8000-000000000007', client_id: CLIENT_ID, title: 'Earlier proceeding', financial_year: '2023-24' },
    ], value => { matterLimit = value }, (column, value) => { matterFilters.set(column, value) }),
    ORG_ID,
    assignmentMetadata({ gstin: '27ABCDE1234F1Z5', financialYears: ['FY 2023-24', '2024-2025'] }),
  )

  assert.deepEqual(result, {
    type: 'ready_to_assign',
    reason: 'Client and financial-year evidence found 3 possible Matters. Choose the destination manually.',
    suggestions: [
      { matterId: MATTER_ID, clientId: CLIENT_ID, reason: 'Possible destination for 2024-25: First proceeding' },
      {
        matterId: '00000000-0000-4000-8000-000000000006',
        clientId: CLIENT_ID,
        reason: 'Possible destination for 2024-25: Parallel proceeding',
      },
      {
        matterId: '00000000-0000-4000-8000-000000000007',
        clientId: CLIENT_ID,
        reason: 'Possible destination for 2023-24: Earlier proceeding',
      },
    ],
  })
  assert.equal(matterLimit, 20)
  assert.equal(matterFilters.get('record_state'), 'active')
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
