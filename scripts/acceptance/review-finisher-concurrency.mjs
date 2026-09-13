import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { requireNode24 } from './runtime.mjs'

requireNode24()
const container = process.env.SUPABASE_DB_CONTAINER
if (container !== 'supabase_db_dms-review-153') throw new Error('Requires the owned disposable Review database.')
const args = ['exec', '-i', container, 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres']
function sql(input) {
  const result = spawnSync('docker', args, { input, encoding: 'utf8', timeout: 15000 })
  if (result.status !== 0) throw new Error(result.stderr || 'Disposable SQL failed')
  return result.stdout.trim()
}
function session(input) {
  const child = spawn('docker', args, { stdio: ['pipe', 'pipe', 'pipe'] })
  let output = ''; let errors = ''
  child.stdout.on('data', bytes => { output += bytes })
  child.stderr.on('data', bytes => { errors += bytes })
  const completed = new Promise((resolve, reject) => child.on('exit', code => code === 0 ? resolve(output.trim()) : reject(new Error(errors))))
  child.stdin.write(input)
  return { child, completed, output: () => output }
}
async function until(predicate) {
  const deadline = Date.now() + 8000
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error('Concurrent fixture did not reach its expected lock state.')
    await new Promise(resolve => setTimeout(resolve, 50))
  }
}
const fixture = readFileSync('supabase/tests/extraction_conflict_review_lifecycle.sql', 'utf8')
const helper = fixture.slice(fixture.indexOf('CREATE FUNCTION pg_temp.'), fixture.indexOf('\nDO $$')).replace('pg_temp.', 'review_acceptance.')
sql(`CREATE SCHEMA review_acceptance; ${helper}`)
try {
  for (const resolutionFirst of [true, false]) {
    const suffix = resolutionFirst ? '7' : '8'
    const doc = `153e0000-0000-0000-0000-00000000000${suffix}`
    const version = `15300000-0000-0000-0000-00000000000${suffix}`
    const item = sql(`SELECT id FROM public.review_items WHERE document_id='${doc}' AND status='needs_review';`)
    const candidate = sql(`SELECT candidate_id FROM public.review_item_evidence WHERE review_item_id='${item}' AND ordinal=2;`)
    const resolve = `SELECT code FROM public.resolve_extraction_conflict('${item}',1,'select_candidate','${candidate}','Race selects OIO',gen_random_uuid());`
    const finish = `SELECT review_acceptance.finish_review_observation('${doc}','SCN',true);`
    const prefix = `BEGIN; SET LOCAL statement_timeout='10s'; SET LOCAL "request.jwt.claim.sub"='153a0000-0000-0000-0000-000000000001';`
    const first = session(`${prefix} SELECT id FROM public.document_versions WHERE id='${version}' FOR UPDATE; ${resolutionFirst ? resolve : finish} SELECT 'ready';\n`)
    let second
    try {
      await until(() => first.output().includes('ready'))
      second = session(`${prefix} SET LOCAL application_name='review-race-second'; ${resolutionFirst ? finish : resolve} COMMIT;\n`)
      second.child.stdin.end()
      await until(() => sql("SELECT count(*) FROM pg_stat_activity WHERE application_name='review-race-second' AND wait_event_type='Lock';") === '1')
      // Both real operations overlap; release only after observing the loser blocked.
      first.child.stdin.end('COMMIT;\n')
      const [firstResult, secondResult] = await Promise.all([first.completed, second.completed])
      assert.ok(resolutionFirst ? firstResult.includes('ok') : secondResult === 'stale')
      const expected = resolutionFirst ? '2:1:2:1:1:1' : '2:1:0:0:0:0'
      assert.equal(sql(`SELECT (SELECT count(*) FROM public.review_items WHERE document_id='${doc}')||':'||(SELECT count(*) FROM public.review_items WHERE document_id='${doc}' AND status='needs_review')||':'||(SELECT count(*) FROM public.document_field_decisions WHERE document_id='${doc}')||':'||(SELECT count(*) FROM public.review_item_decisions r JOIN public.review_items i ON i.id=r.review_item_id WHERE i.document_id='${doc}')||':'||(SELECT count(*) FROM public.activity_events WHERE correlation_id='${item}')||':'||(SELECT count(*) FROM public.activity_projector_outbox_events o JOIN public.activity_events e ON e.id=o.activity_event_id WHERE e.correlation_id='${item}');`), expected)
      assert.equal(sql(`SELECT closure_reason FROM public.review_items WHERE id='${item}';`), resolutionFirst ? 'decision_recorded' : 'source_replaced')
      assert.equal(sql(`SELECT count(*) FROM public.review_item_evidence e JOIN public.review_items i ON i.id=e.review_item_id WHERE i.document_id='${doc}' AND i.status='needs_review';`), resolutionFirst ? '2' : '3')
      assert.equal(sql(`SELECT count(*) FROM public.document_effective_metadata WHERE document_id='${doc}' AND resolution='automatic';`), '0')
      assert.equal(sql(`SELECT count(*) FROM public.document_effective_metadata WHERE document_id='${doc}' AND resolution='accepted' AND winning_document_field_candidate_id='${candidate}';`), resolutionFirst ? '1' : '0')
      console.log(`${resolutionFirst ? 'Resolver-first' : 'Finisher-first'} same-version race passed with observed blocking, exact field/Review/Activity/outbox counts and preserved authority.`)
    } finally {
      if (first.child.exitCode === null) first.child.kill('SIGTERM')
      if (second?.child.exitCode === null) second.child.kill('SIGTERM')
    }
  }
} finally { sql('DROP SCHEMA review_acceptance CASCADE;') }
