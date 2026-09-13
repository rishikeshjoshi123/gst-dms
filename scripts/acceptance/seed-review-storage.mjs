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
const hash = createHash('sha256').update(pdf).digest('hex')
const assetId = '153f0000-0000-0000-0000-000000000001'
const key = `orgs/153b0000-0000-0000-0000-000000000001/assets/${assetId}/original.pdf`
const { data: buckets, error: bucketsError } = await client.storage.listBuckets()
assert.equal(bucketsError, null)
assert.equal(buckets.find(bucket => bucket.id === 'documents')?.public, false)
const { error } = await client.storage.from('documents').upload(key, pdf, { contentType: 'application/pdf', upsert: false })
assert.equal(error, null)
const { data: bytes, error: downloadError } = await client.storage.from('documents').download(key)
assert.equal(downloadError, null)
assert.equal(createHash('sha256').update(Buffer.from(await bytes.arrayBuffer())).digest('hex'), hash)
const { data: asset, error: assetError } = await client.from('file_assets').select('sha256,byte_size,validated_page_count').eq('id', assetId).single()
assert.equal(assetError, null)
assert.deepEqual(asset, { sha256: hash, byte_size: pdf.length, validated_page_count: 4 })
console.log(`Seeded and verified the existing private synthetic PDF (${pdf.length} bytes, four pages) in isolated Review Storage.`)
