import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'

requireNode24()
if (process.env.SUPABASE_DB_CONTAINER !== 'supabase_db_dms-attachment-154') throw new Error('Requires the owned disposable attachment database.')
const args = ['exec', '-i', process.env.SUPABASE_DB_CONTAINER, 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres']
function sql(input) {
  const result = spawnSync('docker', args, { input, encoding: 'utf8', timeout: 15000 })
  if (result.status !== 0) throw new Error(result.stderr)
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
    if (Date.now() > deadline) throw new Error('Attachment concurrency did not reach expected lock state')
    await new Promise(resolve => setTimeout(resolve, 50))
  }
}
const document = '154e0000-0000-0000-0000-000000000001'
const call = n => `SELECT result.code FROM attachment_test.uploads u CROSS JOIN LATERAL public.auto_assign_intended_matter_intake(u.intake_id,u.event_id) result WHERE u.n=${n};`
const first = session(`BEGIN; SET LOCAL statement_timeout='10s'; ${call(1)} SELECT 'ready';\n`)
let second
try {
  await until(() => first.output().includes('ready'))
  second = session(`BEGIN; SET LOCAL statement_timeout='10s'; SET LOCAL application_name='attachment-race-second'; ${call(2)} COMMIT;\n`)
  second.child.stdin.end()
  await until(() => sql("SELECT count(*) FROM pg_stat_activity WHERE application_name='attachment-race-second' AND wait_event_type='Lock';") === '1')
  first.child.stdin.end('COMMIT;\n')
  const [winner, loser] = await Promise.all([first.completed, second.completed])
  assert.ok(winner.includes('ok'))
  assert.equal(loser, 'source_already_attached')
  assert.equal(sql(`SELECT (SELECT count(*) FROM public.document_versions WHERE document_id='${document}')||':'||(SELECT count(*) FROM public.intake_item_assignments WHERE document_id='${document}')||':'||(SELECT count(*) FROM public.activity_events WHERE subject_id='${document}' AND event_type='document.file_attached')||':'||(SELECT count(*) FROM public.outbox_events WHERE aggregate_id='${document}' AND event_kind='document.processing_requested.v1');`), '1:1:1:1')
  assert.equal(sql(`SELECT state||':'||result_code FROM public.document_attachment_intents WHERE intake_item_id=(SELECT intake_id FROM attachment_test.uploads WHERE n=2);`), 'rejected:source_already_attached')
  console.log('Observed simultaneous first attachment: one v1/assignment/Activity/processing intent, explicit nonreplacement loser, no deadlock or timeout.')
} finally {
  if (first.child.exitCode === null) first.child.kill('SIGTERM')
  if (second?.child.exitCode === null) second.child.kill('SIGTERM')
}

for (const trashFirst of [true, false]) {
  const n = trashFirst ? 6 : 5
  const client = `154c0000-0000-0000-0000-00000000000${n}`
  const doc = `154e0000-0000-0000-0000-00000000000${n}`
  const trash = `SELECT code FROM public.trash_resource('client','${client}','attachment.race.${n}');`
  const prefix = `BEGIN; SET LOCAL statement_timeout='10s'; SET LOCAL "request.jwt.claim.sub"='154a0000-0000-0000-0000-000000000001';`
  const lead = session(`${prefix} ${trashFirst ? trash : call(n)} SELECT 'ready';\n`)
  let waiter
  try {
    await until(() => lead.output().includes('ready'))
    assert.ok(lead.output().includes(trashFirst ? 'trashed' : 'ok'), lead.output())
    waiter = session(`${prefix} SET LOCAL application_name='attachment-trash-waiter'; ${trashFirst ? call(n) : trash} COMMIT;\n`)
    waiter.child.stdin.end()
    await until(() => sql("SELECT count(*) FROM pg_stat_activity WHERE application_name='attachment-trash-waiter' AND wait_event_type='Lock';") === '1')
    lead.child.stdin.end('COMMIT;\n')
    const [leadResult, waitResult] = await Promise.all([lead.completed, waiter.completed])
    assert.ok(leadResult.includes(trashFirst ? 'trashed' : 'ok'))
    assert.equal(waitResult, trashFirst ? 'target_unavailable' : 'trashed')
    assert.equal(sql(`SELECT count(*) FROM public.document_versions WHERE document_id='${doc}';`), trashFirst ? '0' : '1')
    assert.equal(sql(`SELECT record_state FROM public.documents WHERE id='${doc}';`), 'trashed')
    assert.equal(sql(`SELECT count(*) FROM public.activity_events WHERE subject_id='${doc}' AND event_type='document.file_attached';`), trashFirst ? '0' : '1')
    console.log(`${trashFirst ? 'Client-Trash-first' : 'Attachment-first'} hierarchical race: observed blocking, correct fenced outcome, no deadlock/timeout.`)
  } finally {
    if (lead.child.exitCode === null) lead.child.kill('SIGTERM')
    if (waiter?.child.exitCode === null) waiter.child.kill('SIGTERM')
  }
}
