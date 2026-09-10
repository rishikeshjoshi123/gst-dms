import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'

import { createClient } from '@supabase/supabase-js'

import { acceptanceProjectPath, requireNode24 } from './runtime.mjs'

const nodeExec = requireNode24()
const supabaseCli = acceptanceProjectPath('node_modules/supabase/dist/supabase.js')
const status = spawnSync(nodeExec, [supabaseCli, 'status', '-o', 'env'], {
  cwd: process.cwd(),
  encoding: 'utf8',
})
if (status.status !== 0) {
  process.stderr.write(status.stderr)
  process.exit(status.status ?? 1)
}

const local = Object.fromEntries(status.stdout.trim().split('\n').map((line) => {
  const separator = line.indexOf('=')
  return [line.slice(0, separator), line.slice(separator + 1).replace(/^"|"$/g, '')]
}))
for (const key of ['API_URL', 'DB_URL', 'INBUCKET_URL', 'STORAGE_S3_URL', 'SERVICE_ROLE_KEY']) {
  if (!local[key]) throw new Error(`Local Supabase did not report ${key}.`)
}
for (const key of ['API_URL', 'DB_URL', 'INBUCKET_URL', 'STORAGE_S3_URL']) {
  const hostname = new URL(local[key]).hostname
  if (hostname !== '127.0.0.1' && hostname !== 'localhost') {
    throw new Error(`Refusing non-loopback ${key} while seeding acceptance Storage.`)
  }
}

const assetId = 'f0010000-0000-0000-0000-000000000001'
const missingAssetId = 'f0010000-0000-0000-0000-000000000002'
const orgId = 'b0010000-0000-0000-0000-000000000001'
const objectKey = `orgs/${orgId}/assets/${assetId}/original.pdf`
const missingObjectKey = `orgs/${orgId}/assets/${missingAssetId}/original.pdf`
const pdf = await readFile(acceptanceProjectPath('tests/acceptance/fixtures/synthetic-multi-page.pdf'))
const sha256 = createHash('sha256').update(pdf).digest('hex')
const supabase = createClient(local.API_URL, local.SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
})

const { data: buckets, error: bucketError } = await supabase.storage.listBuckets()
const documentsBucket = buckets?.find((bucket) => bucket.id === 'documents')
if (bucketError || !documentsBucket || documentsBucket.public) {
  throw new Error('Acceptance requires the local private documents Storage bucket.')
}

const { error: cleanupError } = await supabase.storage
  .from('documents')
  .remove([objectKey, missingObjectKey])
if (cleanupError) throw new Error(`Could not clear disposable acceptance objects: ${cleanupError.message}`)

const { error: uploadError } = await supabase.storage
  .from('documents')
  .upload(objectKey, pdf, { contentType: 'application/pdf', upsert: false })
if (uploadError) throw new Error(`Could not seed the synthetic PDF: ${uploadError.message}`)

const { data: stored, error: downloadError } = await supabase.storage
  .from('documents')
  .download(objectKey)
if (downloadError || !stored) throw new Error('Could not verify the seeded synthetic PDF.')
const storedBytes = Buffer.from(await stored.arrayBuffer())
if (createHash('sha256').update(storedBytes).digest('hex') !== sha256) {
  throw new Error('Seeded PDF bytes do not match the synthetic fixture.')
}

const { data: asset, error: assetError } = await supabase
  .from('file_assets')
  .select('bucket_id, object_key, byte_size, sha256, availability, validated_page_count')
  .eq('id', assetId)
  .eq('org_id', orgId)
  .single()
if (assetError
  || asset.bucket_id !== 'documents'
  || asset.object_key !== objectKey
  || asset.byte_size !== pdf.byteLength
  || asset.sha256 !== sha256
  || asset.availability !== 'available'
  || asset.validated_page_count !== 4) {
  throw new Error('The seeded Storage object does not match its canonical file asset.')
}

const { data: version, error: versionError } = await supabase
  .from('document_versions')
  .select('document_id, asset_id, page_count, validation_state, state')
  .eq('id', 'f1010000-0000-0000-0000-000000000001')
  .single()
if (versionError
  || version.document_id !== 'e0010000-0000-0000-0000-000000000001'
  || version.asset_id !== assetId
  || version.page_count !== 4
  || version.validation_state !== 'valid'
  || version.state !== 'current') {
  throw new Error('The synthetic file asset is not linked through its canonical document version.')
}

const { data: document, error: documentError } = await supabase
  .from('documents')
  .select('current_version_id, effective_size_bytes, content_availability')
  .eq('id', 'e0010000-0000-0000-0000-000000000001')
  .eq('org_id', orgId)
  .single()
if (documentError
  || document.current_version_id !== 'f1010000-0000-0000-0000-000000000001'
  || document.effective_size_bytes !== pdf.byteLength
  || document.content_availability !== 'source_attached') {
  throw new Error('The canonical document does not point at the synthetic PDF version.')
}

const { data: missingBytes } = await supabase.storage.from('documents').download(missingObjectKey)
if (missingBytes) throw new Error('The source-failure fixture unexpectedly has a Storage object.')

process.stdout.write(`Seeded and verified one ${pdf.byteLength}-byte synthetic PDF in local private Storage.\n`)
