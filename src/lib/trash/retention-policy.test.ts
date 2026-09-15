import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import test from 'node:test'

const root = process.cwd()
const read = (file: string) => readFile(path.join(root, file), 'utf8')

test('retention policy exposes exactly 30/60/90 with optimistic concurrency and no manual UI mode', async () => {
  const [migration, section, action] = await Promise.all([
    read('supabase/migrations/00090_trash_retention_policy_and_attention.sql'),
    read('src/app/(app)/settings/TrashRetentionSettingsSection.tsx'),
    read('src/lib/actions/trash-retention.ts'),
  ])

  assert.match(migration, /trash_retention_days IN \(30,60,90\)/)
  assert.match(migration, /trash_retention_days IS NULL[\s\S]*trash_retention_days NOT IN \(30,60,90\)/)
  assert.match(migration, /policy_version=target\.policy_version\+1/)
  assert.match(migration, /settings\.policy_version<>p_expected_policy_version/)
  assert.match(migration, /pg_advisory_xact_lock[\s\S]*hierarchical-resource-trash/)
  assert.deepEqual([...section.matchAll(/value: (\d+), label/g)].map((match) => Number(match[1])), [30, 60, 90])
  assert.doesNotMatch(section, /Switch|manual|indefinite|180|365|auto.?purge/i)
  assert.match(action, /p_expected_policy_version: expectedPolicyVersion/)
  assert.doesNotMatch(action, /createServiceClient|\.from\('organisation_retention_settings'\)/)
})

test('Trash command snapshots the locked policy and creates a schedule without a purge executor', async () => {
  const migration = await read('supabase/migrations/00090_trash_retention_policy_and_attention.sql')
  assert.match(migration, /SELECT target\.\* INTO retention[\s\S]*FOR UPDATE/)
  assert.match(migration, /retention_mode,retention_days,[\s\S]*auto_purge_enabled_snapshot,retention_policy_version,purge_eligible_at,auto_purge_at/)
  assert.match(migration, /'retention_period',retention\.trash_retention_days,true,[\s\S]*retention\.policy_version,v_delete_at,v_delete_at/)
  assert.match(migration, /v_delete_at:=v_now\+pg_catalog\.make_interval/)
  assert.doesNotMatch(migration, /DELETE FROM public\.(clients|matters|documents)|storage\.objects/)
})

test('Team attention remains a dormant operation-keyed projection, while daily IST purge is the pilot schedule', async () => {
  const [migration, worker, dashboard, reader] = await Promise.all([
    read('supabase/migrations/00090_trash_retention_policy_and_attention.sql'),
    read('src/trigger/outbox.ts'),
    read('src/app/(app)/dashboard/page.tsx'),
    read('src/lib/trash/retention-policy.ts'),
  ])
  assert.match(migration, /operation_id uuid PRIMARY KEY/)
  assert.match(migration, /auto_purge_at-interval '24 hours'<=now\(\)/)
  assert.match(migration, /auto_purge_at>now\(\)/)
  assert.match(migration, /ON CONFLICT \(operation_id\) DO NOTHING/)
  assert.match(migration, /NEW\.state NOT IN \('restored','purged'\)/)
  assert.match(migration, /WHEN NEW\.state='restored' THEN 'source_restored'[\s\S]*ELSE 'source_purged'/)
  assert.match(migration, /NOT \('trash\.retention\.manage'=ANY\(actor\.capabilities\)\)/)
  assert.doesNotMatch(migration, /CREATE TABLE public\.trash_retention_team_attention_items[\s\S]{0,900}\b(title|body|content|storage_path)\b/)
  assert.doesNotMatch(worker, /id: 'project-trash-retention-team-attention'/)
  assert.doesNotMatch(worker, /id: 'reconcile-trash-permanent-delete'/)
  assert.match(worker, /id: 'sweep-trash-permanent-delete-daily',[\s\S]*pattern: '0 0 \* \* \*', timezone: 'Asia\/Kolkata'/)
  assert.doesNotMatch(dashboard, /TrashRetentionTeamAttentionPanel|getTrashRetentionTeamAttention/)
  assert.match(reader, /get_trash_retention_team_attention/)
})

test('browser and service clients retain only their intended RPC capabilities', async () => {
  const migration = await read('supabase/migrations/00090_trash_retention_policy_and_attention.sql')
  assert.match(migration, /REVOKE ALL ON TABLE public\.trash_retention_team_attention_items FROM PUBLIC,anon,authenticated,service_role/)
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.project_due_trash_retention_team_attention\(integer\) TO service_role/)
  assert.match(migration, /REVOKE ALL ON FUNCTION[\s\S]*get_organisation_trash_retention_policy\(uuid\)[\s\S]*FROM PUBLIC,anon,service_role/)
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.trash_resource[\s\S]*FROM PUBLIC,anon,service_role/)
})

test('all live Trash callers submit the existing durable outbox wake', async () => {
  const callers = await Promise.all([
    read('src/lib/actions/client.ts'),
    read('src/lib/actions/matter.ts'),
    read('src/lib/actions/document.ts'),
  ])
  for (const caller of callers) {
    assert.match(caller, /rpc\('trash_resource'/)
    assert.match(caller, /scheduleDocumentOutboxWake\(\)/)
  }
})
