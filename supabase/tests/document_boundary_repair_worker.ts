import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { runScopedSearchIndexReprocessWorker, type ScopedSearchIndexClaim } from '../../src/lib/documents/scoped-reprocess'

assert.equal(process.env.SUPABASE_DB_CONTAINER, 'supabase_db_dms')
function sql(command: string): string {
  return execFileSync('docker', ['exec', 'supabase_db_dms', 'psql', '-X', '-qAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', command], { encoding: 'utf8' }).trim()
}
function literal(value: unknown): string {
  if (value === null) return 'NULL'
  if (typeof value === 'number') return String(value)
  return "'" + (typeof value === 'string' ? value : JSON.stringify(value)).replaceAll("'", "''") + "'"
}
async function main() {
  const before = sql('SELECT jsonb_build_array((SELECT count(*) FROM public.file_assets),(SELECT count(*) FROM public.source_analysis_runs))')
  const result = JSON.parse(sql(`BEGIN; SET LOCAL ROLE authenticated; SET LOCAL "request.jwt.claim.sub"='152a0000-0000-0000-0000-000000000001'; SELECT public.execute_document_boundary_repair('152e0000-0000-0000-0000-000000000002','152d0000-0000-0000-0000-000000000002','copy',public.preview_document_boundary_repair('152e0000-0000-0000-0000-000000000002','152d0000-0000-0000-0000-000000000002','copy')->>'fingerprint','Worker acquisition fixture','15290000-0000-0000-0000-000000000004'); COMMIT;`))
  assert.equal(result.code, 'ok')
  const event = sql(`SELECT id FROM public.outbox_events WHERE aggregate_id=${literal(result.documentId)} AND idempotency_key LIKE 'document.repair.search.%'`)
  const token = '15290000-0000-0000-0000-000000000005'
  sql(`UPDATE public.outbox_events SET delivery_state='leased',lease_token='${token}',lease_expires_at=now()+interval '2 minutes',delivered_at=NULL,failed_at=NULL WHERE id=${literal(event)}`)
  const claim: ScopedSearchIndexClaim = JSON.parse(sql(`BEGIN; SET LOCAL ROLE service_role; SELECT row_to_json(r) FROM public.claim_document_search_index_reprocess_work(${literal(event)},'boundary-worker-fixture','152b0000-0000-0000-0000-000000000001','${token}') r; COMMIT;`))
  assert.equal(claim.code, 'claimed')
  const allowed = new Set(['get_document_search_index_reprocess_input', 'get_document_search_page_text_reprocess_input', 'write_current_document_search_page_chunks', 'finish_document_search_index_reprocess_work'])
  let embeddingCalls = 0
  const outcome = await runScopedSearchIndexReprocessWorker({ async rpc(name, args) {
    assert(allowed.has(name))
    const parameters = Object.entries(args).map(([key, value]) => {
      assert(/^p_[a-z_]+$/.test(key))
      return `${key}=>${literal(value)}`
    }).join(',')
    const row = name === 'finish_document_search_index_reprocess_work' ? "jsonb_build_object('code',r)" : 'to_jsonb(r)'
    const data = JSON.parse(sql(`BEGIN; SET LOCAL ROLE service_role; SELECT coalesce(jsonb_agg(${row}),'[]') FROM public.${name}(${parameters}) r; COMMIT;`))
    console.log(name, data[0]?.code)
    return { data, error: null }
  } }, claim, { async embed() {
    embeddingCalls++
    return { embedding: Array(768).fill(0.1), dimensions: 768, inputTokens: 7, billableUsage: null, truncated: false, model: 'gemini-embedding-001', version: 'gemini-embedding-001-768-v1', purpose: 'corpus' }
  } })
  assert.equal(outcome.outcome, 'indexed')
  assert(embeddingCalls >= 2, 'real worker must index both page passages and metadata')
  assert.equal(sql('SELECT jsonb_build_array((SELECT count(*) FROM public.file_assets),(SELECT count(*) FROM public.source_analysis_runs))'), before)
  assert.equal(sql(`SELECT count(*)>0 FROM public.search_document_chunks WHERE document_id=${literal(result.documentId)} AND document_version_id=${literal(claim.document_version_id)}`), 't')
  assert.equal(sql(`SELECT count(*)=1 FROM public.search_items WHERE document_id=${literal(result.documentId)} AND document_version_id=${literal(claim.document_version_id)} AND matter_id='152d0000-0000-0000-0000-000000000002'`), 't')
  assert.equal(sql(`SELECT count(*)=1 FROM public.document_page_text_artifacts a JOIN public.document_page_text_artifacts original ON original.id=a.copied_from_artifact_id WHERE a.document_id=${literal(result.documentId)} AND original.document_id='152e0000-0000-0000-0000-000000000002' AND a.content_fingerprint=original.content_fingerprint`), 't')
  console.log('Copy real scoped worker indexed retained acquisition into destination passages without new asset/base extraction.')
}
void main()
