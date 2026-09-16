import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { createClient } from '@supabase/supabase-js'
import { requireNode24 } from './runtime.mjs'

const node = requireNode24()
const workdir = process.env.REVIEW_ACCEPTANCE_WORKDIR
if (!workdir || !readFileSync(join(workdir, 'supabase/config.toml'), 'utf8').includes('project_id = "dms-review-153"')) throw new Error('Requires the owned disposable Review project.')
const status = spawnSync(node, ['node_modules/supabase/dist/supabase.js', 'status', '--workdir', workdir, '-o', 'json'], { encoding: 'utf8' })
if (status.status !== 0) throw new Error('Disposable project status unavailable.')
const local = JSON.parse(status.stdout)
assert.equal(local.API_URL, 'http://127.0.0.1:55321')
assert.equal(new URL(local.DB_URL).port, '55322')
const client = createClient(local.API_URL, local.SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } })
const pdf = readFileSync('tests/acceptance/fixtures/synthetic-multi-page.pdf')
const conflictOnly=process.env.REVIEW_ACCEPTANCE_CONFLICT_ONLY==='1'
const placementPdf=conflictOnly?readFileSync('tests/acceptance/fixtures/synthetic-placement-conflict.pdf'):null
const secondPlacementPdf=conflictOnly?readFileSync('tests/acceptance/fixtures/synthetic-placement-conflict-second.pdf'):null
const group=process.env.REVIEW_ACCEPTANCE_GROUP==='1'
const sources = conflictOnly ? [
  {orgId:'152b0000-0000-0000-0000-000000000001',assetId:'152f0000-0000-0000-0000-000000000001',bytes:placementPdf},
  {orgId:'152b0000-0000-0000-0000-000000000001',assetId:'152f0000-0000-0000-0000-000000000002',bytes:secondPlacementPdf},
  ...(group?[{orgId:'152b0000-0000-0000-0000-000000000001',assetId:'152f0000-0000-0000-0000-000000000003',
    bytes:Buffer.concat([placementPdf,Buffer.from('\n% grouped-third-source\n')])}]:[]),
] : [
  {orgId:'153b0000-0000-0000-0000-000000000001',assetId: '153f0000-0000-0000-0000-000000000001', bytes: pdf },
  ...(process.env.REVIEW_ACCEPTANCE_DATE_ONLY === '1' ? [] :
    [{orgId:'153b0000-0000-0000-0000-000000000001',assetId: '164f0000-0000-0000-0000-000000000001', bytes: Buffer.concat([pdf, Buffer.from('\n% placement fixture\n')]) }]),
]
const { data: buckets, error: bucketsError } = await client.storage.listBuckets()
assert.equal(bucketsError, null)
assert.equal(buckets.find(bucket => bucket.id === 'documents')?.public, false)
for (const { orgId,assetId, bytes: sourceBytes } of sources) {
  const key = `orgs/${orgId}/assets/${assetId}/original.pdf`
  const { error } = await client.storage.from('documents').upload(key, sourceBytes, { contentType: 'application/pdf', upsert: false })
  assert.equal(error, null)
  const { data: bytes, error: downloadError } = await client.storage.from('documents').download(key)
  assert.equal(downloadError, null)
  const expectedHash = createHash('sha256').update(sourceBytes).digest('hex')
  assert.equal(createHash('sha256').update(Buffer.from(await bytes.arrayBuffer())).digest('hex'), expectedHash)
  // Later force-RLS lifecycle migrations intentionally remove service-role
  // direct table reads. Inspect this known isolated fixture via local psql,
  // without weakening the application's private file-asset boundary.
  const inspected=spawnSync('docker',['exec','supabase_db_dms-review-153','psql','-X','-qAt',
    '-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres','-c',
    `SELECT sha256||':'||byte_size||':'||validated_page_count FROM public.file_assets WHERE id='${assetId}'`],
    {encoding:'utf8'})
  assert.equal(inspected.status,0,inspected.stderr)
  assert.equal(inspected.stdout.trim(),`${expectedHash}:${sourceBytes.length}:${conflictOnly?1:4}`)
}
console.log(`Seeded and verified ${sources.length} private synthetic ${conflictOnly?'one-page':'four-page'} PDFs in isolated Review Storage.`)
