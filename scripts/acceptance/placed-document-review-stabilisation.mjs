import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { requireNode24 } from './runtime.mjs'

requireNode24()
const container = process.env.SUPABASE_DB_CONTAINER
if (container !== 'supabase_db_dms-review-153') throw new Error('Requires the owned disposable Review database.')
const args = ['exec', '-i', container, 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres']
const owner = '152a0000-0000-0000-0000-000000000001'
const sourceMatter = '152d0000-0000-0000-0000-000000000001'
const targetB = '152d0000-0000-0000-0000-000000000002'
const targetC = '169d0000-0000-0000-0000-000000000003'
const singleDoc = '152e0000-0000-0000-0000-000000000001'
const multiDoc = '152e0000-0000-0000-0000-000000000002'
const expectedVersions = new Map([[singleDoc, '15200000-0000-0000-0000-000000000001'], [multiDoc, '15200000-0000-0000-0000-000000000002']])
const expectedAssets = new Map([[singleDoc, '152f0000-0000-0000-0000-000000000001'], [multiDoc, '152f0000-0000-0000-0000-000000000002']])
function sql(input) {
  const result = spawnSync('docker', args, { input, encoding: 'utf8', timeout: 20000 })
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
  const deadline = Date.now() + 10000
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error('Two-session fixture did not reach observed blocking.')
    await new Promise(resolve => setTimeout(resolve, 50))
  }
}
function actorSql(input) {
  return sql(`BEGIN; SET LOCAL "request.jwt.claim.role"='authenticated'; SET LOCAL "request.jwt.claim.sub"='${owner}'; ${input} COMMIT;`)
}
function item(doc, type) {
  const id = sql(`SELECT id FROM public.review_items WHERE document_id='${doc}' AND type='${type}' AND status='needs_review';`)
  assert.match(id, /^[0-9a-f-]{36}$/)
  return id
}
function fingerprint(doc, target) {
  const value = actorSql(`SELECT public.preview_document_boundary_repair('${doc}','${target}','move')->>'fingerprint';`)
  assert.match(value, /^[0-9a-f]{64}$/)
  return value
}
function state(doc, itemId, type) {
  return sql(`SELECT d.matter_id||':'||d.current_version_id||':'||v.asset_id||':'||i.status||':'||i.revision||':'||
    (SELECT count(*) FROM public.document_boundary_repair_receipts WHERE source_document_id=d.id)||':'||
    (SELECT count(*) FROM public.${type}_decisions WHERE review_item_id=i.id)||':'||
    (SELECT count(*) FROM public.activity_events WHERE subject_id=d.id AND event_type IN
      ('document.boundary_repaired','review.${type === 'placement_conflict' ? 'placement_conflict' : 'multi_placement_conflict'}_decided'))
    FROM public.documents d JOIN public.document_versions v ON v.id=d.current_version_id
      JOIN public.review_items i ON i.id='${itemId}' WHERE d.id='${doc}';`)
}
function assertExactSource(doc) {
  assert.equal(sql(`SELECT d.current_version_id||':'||v.asset_id FROM public.documents d
    JOIN public.document_versions v ON v.id=d.current_version_id WHERE d.id='${doc}';`),
  `${expectedVersions.get(doc)}:${expectedAssets.get(doc)}`)
}
function installFault(type) {
  sql(`CREATE OR REPLACE FUNCTION review_acceptance.fail_after_inner_move() RETURNS trigger
    LANGUAGE plpgsql AS $$ BEGIN
      IF NOT EXISTS(SELECT 1 FROM public.document_boundary_repair_receipts
        WHERE idempotency_key=NEW.idempotency_key AND mode='move')
        THEN RAISE EXCEPTION 'Late fault was reached before governed Move'; END IF;
      IF NOT EXISTS(SELECT 1 FROM public.documents d JOIN public.review_items i ON i.document_id=d.id
        WHERE i.id=NEW.review_item_id AND d.matter_id<>NEW.old_matter_id)
        THEN RAISE EXCEPTION 'Late fault was reached before document destination changed'; END IF;
      RAISE EXCEPTION USING ERRCODE='Z8051',MESSAGE='synthetic late Review fault';
    END $$;
    CREATE TRIGGER review_acceptance_late_fault BEFORE INSERT ON public.${type}_decisions
      FOR EACH ROW EXECUTE FUNCTION review_acceptance.fail_after_inner_move();`)
}
function removeFault(type) {
  sql(`DROP TRIGGER review_acceptance_late_fault ON public.${type}_decisions;`)
}
function fault(type, doc, itemId, target, command) {
  const before = state(doc, itemId, type)
  installFault(type)
  try {
    assert.equal(actorSql(command), 'failed')
    assert.equal(state(doc, itemId, type), before, 'Late fault left a partial governed Move/Review/Activity')
    assertExactSource(doc)
    console.log(`${type} deliberate post-inner-Move fault failed closed with zero durable partial effects.`)
  } finally { removeFault(type) }
}
async function compete({ name, doc, itemId, first, second, type, target }) {
  const prefix = `BEGIN; SET LOCAL statement_timeout='12s'; SET LOCAL "request.jwt.claim.role"='authenticated'; SET LOCAL "request.jwt.claim.sub"='${owner}';`
  const winner = session(`${prefix} SELECT code FROM ${first}; SELECT 'ready';\n`)
  let loser
  try {
    await until(() => winner.output().includes('ready'))
    loser = session(`${prefix} SET LOCAL application_name='review-stabilisation-loser'; SELECT code FROM ${second}; COMMIT;\n`)
    loser.child.stdin.end()
    await until(() => sql("SELECT count(*) FROM pg_stat_activity WHERE application_name='review-stabilisation-loser' AND wait_event_type='Lock';") === '1')
    winner.child.stdin.end('COMMIT;\n')
    const [won, lost] = await Promise.all([winner.completed, loser.completed])
    assert.ok(won.includes('ok'))
    assert.equal(lost, 'stale')
    assert.equal(sql(`SELECT matter_id FROM public.documents WHERE id='${doc}';`), target)
    assert.equal(sql(`SELECT status||':'||closure_reason||':'||revision FROM public.review_items WHERE id='${itemId}';`), 'closed:decision_recorded:2')
    assert.equal(sql(`SELECT count(*) FROM public.${type}_decisions WHERE review_item_id='${itemId}';`), '1')
    assert.equal(sql(`SELECT count(*) FROM public.review_items WHERE document_id='${doc}' AND status='needs_review'
      AND type IN ('placement_conflict','multi_placement_conflict');`), '0')
    assert.equal(sql(`SELECT count(*) FROM public.document_boundary_repair_receipts WHERE source_document_id='${doc}' AND mode='move';`), '1')
    assert.equal(sql(`SELECT count(*) FROM public.activity_events WHERE subject_id='${doc}' AND event_type='document.boundary_repaired';`), '1')
    assert.equal(sql(`SELECT count(*) FROM public.activity_events WHERE subject_id='${doc}' AND event_type='review.${type}_decided';`), '1')
    assertExactSource(doc)
    console.log(`${name}: observed two-session resolver blocking; one Move, one Review decision and exact source; competing command stale.`)
  } finally {
    if (winner.child.exitCode === null) winner.child.kill('SIGTERM')
    if (loser?.child.exitCode === null) loser.child.kill('SIGTERM')
  }
}
async function mutationBeforeResolver({ name, mutate, resolve, doc, itemId, type }) {
  const before = state(doc, itemId, type)
  const prefix = `BEGIN; SET LOCAL statement_timeout='12s'; SET LOCAL "request.jwt.claim.role"='authenticated'; SET LOCAL "request.jwt.claim.sub"='${owner}';`
  const mutation = session(`${prefix} ${mutate} SELECT 'ready';\n`)
  let resolver
  try {
    await until(() => mutation.output().includes('ready'))
    resolver = session(`${prefix} SET LOCAL application_name='review-stabilisation-mutation-resolver';
      SELECT code FROM ${resolve}; ROLLBACK;\n`)
    resolver.child.stdin.end()
    await until(() => sql("SELECT count(*) FROM pg_stat_activity WHERE application_name='review-stabilisation-mutation-resolver' AND wait_event_type='Lock';") === '1')
    mutation.child.stdin.end('ROLLBACK;\n')
    const [mutated, resolved] = await Promise.all([mutation.completed, resolver.completed])
    assert.ok(mutated.includes('ready'))
    assert.equal(resolved, 'ok')
    assert.equal(state(doc, itemId, type), before)
    assertExactSource(doc)
    console.log(`${name}: observed mutation-versus-resolver blocking; both diagnostic transactions rolled back without durable effects.`)
  } finally {
    if (mutation.child.exitCode === null) mutation.child.kill('SIGTERM')
    if (resolver?.child.exitCode === null) resolver.child.kill('SIGTERM')
  }
}
async function committedTrashBeforeResolver({ doc, itemId, resolve }) {
  const prefix = `BEGIN; SET LOCAL statement_timeout='12s'; SET LOCAL "request.jwt.claim.role"='authenticated'; SET LOCAL "request.jwt.claim.sub"='${owner}';`
  const mutation = session(`${prefix} SELECT code FROM public.trash_resource('matter','${targetC}',
    'synthetic.committed-concurrent-trash'); SELECT 'ready';\n`)
  let resolver
  try {
    await until(() => mutation.output().includes('ready'))
    resolver = session(`${prefix} SET LOCAL application_name='review-stabilisation-committed-trash-resolver';
      SELECT code FROM ${resolve}; COMMIT;\n`)
    resolver.child.stdin.end()
    await until(() => sql("SELECT count(*) FROM pg_stat_activity WHERE application_name='review-stabilisation-committed-trash-resolver' AND wait_event_type='Lock';") === '1')
    mutation.child.stdin.end('COMMIT;\n')
    const [mutated, resolved] = await Promise.all([mutation.completed, resolver.completed])
    assert.ok(mutated.includes('trashed'))
    assert.equal(resolved, 'stale')
    assert.equal(sql(`SELECT matter_id FROM public.documents WHERE id='${doc}';`), sourceMatter)
    assert.equal(sql(`SELECT count(*) FROM public.document_boundary_repair_receipts WHERE source_document_id='${doc}';`), '0')
    assert.equal(sql(`SELECT count(*) FROM public.multi_placement_conflict_decisions WHERE review_item_id='${itemId}';`), '0')
    assert.equal(sql(`SELECT count(*) FROM public.activity_events WHERE subject_id='${doc}' AND event_type IN
      ('document.boundary_repaired','review.multi_placement_conflict_decided');`), '0')
    assertExactSource(doc)
    console.log('Committed Matter Trash won an observed two-session race; resolver stale with zero Move/Review/Activity.')
  } finally {
    if (mutation.child.exitCode === null) mutation.child.kill('SIGTERM')
    if (resolver?.child.exitCode === null) resolver.child.kill('SIGTERM')
  }
  const operation = sql(`SELECT id FROM public.trash_operations WHERE root_resource_type='matter'
    AND root_resource_id='${targetC}' AND state='trashed' ORDER BY created_at DESC LIMIT 1;`)
  assert.match(operation, /^[0-9a-f-]{36}$/)
  assert.equal(actorSql(`SELECT code FROM public.restore_trash_operation('${operation}',
    'synthetic.restore-after-committed-race');`), 'restored')
  assertExactSource(doc)
  console.log('Governed Matter Restore restored the fixture for the next current Review decision.')
}
async function committedMutationBeforeResolver({ name, mutate, resolve, doc, itemId, restore, expectedMutationCode }) {
  const prefix = `BEGIN; SET LOCAL statement_timeout='12s'; SET LOCAL "request.jwt.claim.role"='authenticated'; SET LOCAL "request.jwt.claim.sub"='${owner}';`
  const mutation = session(`${prefix} ${mutate} SELECT 'ready';\n`)
  let resolver
  try {
    await until(() => mutation.output().includes('ready'))
    resolver = session(`${prefix} SET LOCAL application_name='review-stabilisation-committed-mutation-resolver';
      SELECT code FROM ${resolve}; COMMIT;\n`)
    resolver.child.stdin.end()
    await until(() => sql("SELECT count(*) FROM pg_stat_activity WHERE application_name='review-stabilisation-committed-mutation-resolver' AND wait_event_type='Lock';") === '1')
    mutation.child.stdin.end('COMMIT;\n')
    const [mutated, resolved] = await Promise.all([mutation.completed, resolver.completed])
    assert.ok(mutated.includes('ready'))
    if (expectedMutationCode) assert.ok(mutated.includes(expectedMutationCode))
    assert.equal(resolved, 'stale')
    assert.equal(sql(`SELECT matter_id FROM public.documents WHERE id='${doc}';`), sourceMatter)
    assert.equal(sql(`SELECT count(*) FROM public.document_boundary_repair_receipts WHERE source_document_id='${doc}';`), '0')
    assert.equal(sql(`SELECT count(*) FROM public.multi_placement_conflict_decisions WHERE review_item_id='${itemId}';`), '0')
    assert.equal(sql(`SELECT count(*) FROM public.activity_events WHERE subject_id='${doc}' AND event_type IN
      ('document.boundary_repaired','review.multi_placement_conflict_decided');`), '0')
    console.log(`${name}: committed mutation won observed lock; resolver stale with zero Move/Review/Activity.`)
  } finally {
    if (mutation.child.exitCode === null) mutation.child.kill('SIGTERM')
    if (resolver?.child.exitCode === null) resolver.child.kill('SIGTERM')
  }
  restore()
  assertExactSource(doc)
}

sql('CREATE SCHEMA review_acceptance;')
try {
  sql(readFileSync('supabase/tests/placed_document_review_stabilisation_setup.sql', 'utf8'))
  const firstItem = item(singleDoc, 'placement_conflict')
  const secondItem = item(multiDoc, 'placement_conflict')
  const firstImpact = fingerprint(singleDoc, targetB)
  const secondImpact = fingerprint(multiDoc, targetB)
  fault('placement_conflict', multiDoc, secondItem, targetB,
    `SELECT code FROM public.resolve_placement_conflict('${secondItem}',1,'move','${secondImpact}',
      'Synthetic late fault', '${randomUUID()}');`)
  await compete({ name: 'Single-target Move versus Keep', doc: singleDoc, itemId: firstItem,
    first: `public.resolve_placement_conflict('${firstItem}',1,'move','${firstImpact}','Choose verified target','${randomUUID()}')`,
    second: `public.resolve_placement_conflict('${firstItem}',1,'keep',NULL,'Keep old filing','${randomUUID()}')`,
    type: 'placement_conflict', target: targetB })
  sql(readFileSync('supabase/tests/multi_placed_document_review_stabilisation_setup.sql', 'utf8'))
  let thirdItem = item(multiDoc, 'multi_placement_conflict')
  let thirdImpact = fingerprint(multiDoc, targetC)
  const targetIdentifier = sql(`SELECT target_identifier_id FROM public.multi_placement_conflict_sources
    WHERE review_item_id='${thirdItem}' AND target_matter_id='${targetC}';`)
  const identifierRevision = sql(`SELECT revision FROM public.matter_identifiers WHERE id='${targetIdentifier}';`)
  const matterRevision = sql(`SELECT revision FROM public.matters WHERE id='${targetC}';`)
  const tentativeMove = `public.resolve_multi_placement_conflict('${thirdItem}',1,'move','${targetC}',
    '${thirdImpact}','Diagnostic governed Move','${randomUUID()}')`
  await mutationBeforeResolver({ name: 'Human verified-key revocation', doc: multiDoc, itemId: thirdItem,
    type: 'multi_placement_conflict',
    mutate: `SELECT code FROM public.revoke_matter_identifier('${targetIdentifier}',${identifierRevision},${matterRevision},
      'Synthetic concurrent verified correction','${randomUUID()}');`, resolve: tentativeMove })
  await mutationBeforeResolver({ name: 'Document current-source transition', doc: multiDoc, itemId: thirdItem,
    type: 'multi_placement_conflict',
    mutate: `UPDATE public.documents SET current_version_id=NULL WHERE id='${multiDoc}';`, resolve: tentativeMove })
  await mutationBeforeResolver({ name: 'Matter Trash transition', doc: multiDoc, itemId: thirdItem,
    type: 'multi_placement_conflict',
    mutate: `SELECT code FROM public.trash_resource('matter','${targetC}','synthetic.concurrent-trash');`,
    resolve: tentativeMove })
  await committedMutationBeforeResolver({ name: 'Committed current-source transition', doc: multiDoc,
    itemId: thirdItem, resolve: tentativeMove,
    mutate: `UPDATE public.documents SET current_version_id=NULL WHERE id='${multiDoc}';`,
    restore: () => {
      sql(`UPDATE public.documents SET current_version_id='${expectedVersions.get(multiDoc)}'
        WHERE id='${multiDoc}';`)
      actorSql(`SELECT public.reconcile_placed_document_identity_conflict('${multiDoc}');`)
    } })
  thirdItem = item(multiDoc, 'multi_placement_conflict')
  thirdImpact = fingerprint(multiDoc, targetC)
  const currentKeyId = sql(`SELECT target_identifier_id FROM public.multi_placement_conflict_sources
    WHERE review_item_id='${thirdItem}' AND target_matter_id='${targetC}';`)
  const currentKeyRevision = sql(`SELECT revision FROM public.matter_identifiers WHERE id='${currentKeyId}';`)
  const currentMatterRevision = sql(`SELECT revision FROM public.matters WHERE id='${targetC}';`)
  await committedMutationBeforeResolver({ name: 'Committed human verified-key correction', doc: multiDoc,
    itemId: thirdItem, resolve: `public.resolve_multi_placement_conflict('${thirdItem}',1,'move','${targetC}',
      '${thirdImpact}','Diagnostic governed Move','${randomUUID()}')`,
    expectedMutationCode: 'ok',
    mutate: `SELECT code FROM public.revoke_matter_identifier('${currentKeyId}',${currentKeyRevision},
      ${currentMatterRevision},'Synthetic committed key correction','${randomUUID()}');`,
    restore: () => {
      const rev = sql(`SELECT revision FROM public.matters WHERE id='${targetC}';`)
      assert.equal(actorSql(`SELECT code FROM public.activate_matter_identifier('${targetC}',${rev},
        'order_reference','self_identifier','GST Tribunal','GST/556/2026','GST/556/2026',
        '169e0000-0000-0000-0000-000000000003','16900000-0000-0000-0000-000000000003',
        1,'GST/556/2026','[]','Synthetic re-verification after committed race','${randomUUID()}');`), 'ok')
    } })
  thirdItem = item(multiDoc, 'multi_placement_conflict')
  thirdImpact = fingerprint(multiDoc, targetC)
  await committedTrashBeforeResolver({ doc: multiDoc, itemId: thirdItem,
    resolve: `public.resolve_multi_placement_conflict('${thirdItem}',1,'move','${targetC}',
      '${thirdImpact}','Diagnostic governed Move','${randomUUID()}')` })
  thirdItem = item(multiDoc, 'multi_placement_conflict')
  thirdImpact = fingerprint(multiDoc, targetC)
  fault('multi_placement_conflict', multiDoc, thirdItem, targetC,
    `SELECT code FROM public.resolve_multi_placement_conflict('${thirdItem}',1,'move','${targetC}','${thirdImpact}',
      'Synthetic late fault','${randomUUID()}');`)
  await compete({ name: 'Multi-target chosen Move versus Keep', doc: multiDoc, itemId: thirdItem,
    first: `public.resolve_multi_placement_conflict('${thirdItem}',1,'move','${targetC}','${thirdImpact}','Choose verified C','${randomUUID()}')`,
    second: `public.resolve_multi_placement_conflict('${thirdItem}',1,'keep',NULL,NULL,'Keep old filing','${randomUUID()}')`,
    type: 'multi_placement_conflict', target: targetC })
} finally { sql('DROP SCHEMA review_acceptance CASCADE;') }
