import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const migration = new URL('../../../supabase/migrations/00138_direct_upload_lifecycle_hardening.sql', import.meta.url)
const sqlAcceptance = new URL('../../../supabase/tests/document_upload_commands.sql', import.meta.url)
const action = new URL('../actions/document.ts', import.meta.url)
const callers = [
  new URL('../../app/(app)/dashboard/GlobalDropzone.tsx', import.meta.url),
  new URL('../../app/(app)/inbox/UploadModal.tsx', import.meta.url),
  new URL('../../app/(app)/matters/[id]/Dropzone.tsx', import.meta.url),
]

test('migration conservatively accounts signed sessions and serializes exact-identity cancel/finalize', async () => {
  const source = await readFile(migration, 'utf8')
  assert.match(source, /SET reserved_bytes=52428800/)
  assert.match(source, /v_unobserved_ceiling constant bigint:=52428800/)
  assert.match(source, /v_used\+v_reserved\+v_unobserved_ceiling/)
  assert.match(source, /byte_size=coalesce\(byte_size,v_unobserved_ceiling\)[\s\S]*availability='expired'/)
  assert.match(source, /WHERE us\.id=p_session FOR UPDATE/)
  assert.match(source, /s\.org_id IS DISTINCT FROM p_org/)
  assert.match(source, /s\.created_by IS DISTINCT FROM p_actor/)
  assert.match(source, /s\.idempotency_key IS DISTINCT FROM p_idempotency/)
  assert.match(source, /command='complete' AND cr\.idempotency_key=p_idempotency/)
  assert.match(source, /CREATE FUNCTION public\.cancel_document_upload/)
  assert.match(source, /state='cancelled'/)
  assert.match(source, /byte_size=coalesce\(fa\.byte_size,v_unobserved_ceiling\)[\s\S]*availability='failed'/)
  assert.match(source, /s\.state IN \('finalized','expired','failed','cancelled'\)/)
  assert.match(source, /us\.expires_at\+interval '2 hours 5 minutes'>now\(\)/)
})

test('rollback SQL acceptance covers forged accounting, expiry, replay, race winners, and deletion accounting', async () => {
  const source = await readFile(sqlAcceptance, 'utf8')
  for (const evidence of [
    'unobserved signed session must reserve Storage ceiling',
    'cross identity completion receipt replay',
    'wrong idempotency receipt replay',
    'finalize must win before later cancel',
    'cancel winner/accounting',
    'cancelled upload finalized',
    'observed quota recheck',
    'expiry maintenance/accounting',
    'quota must equal physically retained assets',
  ]) assert.match(source, new RegExp(evidence))
})

test('server actions expose UUID-only cancel/finalize inputs and defer object deletion through token expiry', async () => {
  const source = await readFile(action, 'utf8')
  const boundary = source.slice(source.indexOf('type DocumentUploadReservationInput'), source.indexOf('function resumableStorageEndpoint'))
  assert.match(boundary, /type DocumentUploadCancelInput = DocumentUploadFinalizationInput/)
  assert.match(boundary, /uploadIdempotencyKey\(input\.uploadSessionId\)/)
  assert.match(boundary, /get_document_upload_completion_receipt/)
  assert.match(boundary, /cancel_document_upload/)
  assert.match(boundary, /p_actor: user\.id/)
  assert.match(boundary, /p_org: orgId/)
  assert.match(boundary, /outcome\.code !== 'cancelled'/)
  assert.match(boundary, /completion\.code === 'cancelled'/)
  assert.match(boundary, /cleanup waits for token expiry/)
  assert.doesNotMatch(boundary, /\.remove\(\[asset\.object_key\]\)/)
  assert.doesNotMatch(boundary, /record_document_asset_storage_deleted/)
  assert.doesNotMatch(boundary, /FormData|\bas File\b/)
})

test('all live upload callers recover identity and expose a labelled 44px transfer cancel action', async () => {
  for (const caller of callers) {
    const source = await readFile(caller, 'utf8')
    assert.match(source, /documentUploadIdempotencyKey/)
    assert.match(source, /\.cancel\(\)/)
    assert.match(source, />\s*\{[^}]*\? 'Cancelling…' : 'Cancel'\}\s*</)
    assert.match(source, /min-h-11/)
    assert.match(source, /'cancelled' in/)
  }
})

test('the shared upload modal keeps an all-cancelled batch open for same-file reselection', async () => {
  const source = await readFile(callers[1], 'utf8')

  assert.match(source, /let hasCancelledOutcome = false/)
  assert.match(source, /if \('cancelled' in res\) \{\s*hasCancelledOutcome = true/)
  assert.match(source, /!hasTerminalOutcome && !hasCancelledOutcome/)
})
