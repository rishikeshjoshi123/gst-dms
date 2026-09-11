import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'

import { createClient } from '@supabase/supabase-js'

import { acceptanceProjectPath, requireNode24 } from './runtime.mjs'

const completedFilename = 'acceptance-browser-complete.pdf'
const cancelledFilename = 'acceptance-browser-cancel.pdf'
const ownerId = 'a0010000-0000-0000-0000-000000000001'
const orgId = 'b0010000-0000-0000-0000-000000000001'
const completionSuffix = '\n% CaseChain browser upload completion fixture\n'
const sharedSuffix = '\n% CaseChain shared Intake source\n'
const sharedAssetId = 'f0010000-0000-0000-0000-000000000003'

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
    throw new Error(`Refusing non-loopback ${key} while verifying browser uploads.`)
  }
}

const supabase = createClient(local.API_URL, local.SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
})
const { data: sessions, error: sessionsError } = await supabase
  .from('upload_sessions')
  .select('id, asset_id, declared_filename, declared_byte_size, state, failure_code, created_by, org_id')
  .in('declared_filename', [completedFilename, cancelledFilename])
  .order('created_at', { ascending: true })
if (sessionsError) throw new Error(`Could not inspect browser upload sessions: ${sessionsError.message}`)

const browserSessions = sessions ?? []
const completed = browserSessions.filter(session => session.declared_filename === completedFilename)
const cancelled = browserSessions.filter(session => session.declared_filename === cancelledFilename)
if (completed.length !== 1 || completed[0].state !== 'finalized') {
  throw new Error('Expected exactly one finalized browser upload session.')
}
if (cancelled.length !== 2 || cancelled.some(session => session.state !== 'cancelled' || session.failure_code !== 'upload_cancelled')) {
  throw new Error('Expected two independently cancelled sessions after same-file reselection.')
}
if (browserSessions.some(session => session.created_by !== ownerId || session.org_id !== orgId)) {
  throw new Error('Browser upload sessions escaped the synthetic owner tenant.')
}

const sessionIds = browserSessions.map(session => session.id)
const assetIds = browserSessions.map(session => session.asset_id)
const [{ data: intakes, error: intakeError }, { data: assets, error: assetError }, { data: reservations, error: reservationError }, { data: receipts, error: receiptError }] = await Promise.all([
  supabase.from('intake_items').select('upload_session_id, state, failure_code, intended_matter_id').in('upload_session_id', sessionIds),
  supabase.from('file_assets').select('id, bucket_id, object_key, byte_size, sha256, detected_mime_type, availability, failure_code').in('id', assetIds),
  supabase.from('storage_reservations').select('upload_session_id, state').in('upload_session_id', sessionIds),
  supabase.from('document_upload_command_receipts').select('upload_session_id, command, code').in('upload_session_id', sessionIds),
])
if (intakeError || assetError || reservationError || receiptError) {
  throw new Error(`Could not inspect authoritative upload lineage: ${intakeError?.message ?? assetError?.message ?? reservationError?.message ?? receiptError?.message}`)
}

const completedSession = completed[0]
const completedIntake = intakes.find(intake => intake.upload_session_id === completedSession.id)
const completedAsset = assets.find(asset => asset.id === completedSession.asset_id)
const completedReservation = reservations.find(reservation => reservation.upload_session_id === completedSession.id)
const completedReceipt = receipts.find(receipt => receipt.upload_session_id === completedSession.id && receipt.command === 'complete')
const sourcePdf = await readFile(acceptanceProjectPath('tests/acceptance/fixtures/synthetic-multi-page.pdf'))
const expectedBytes = Buffer.concat([sourcePdf, Buffer.from(completionSuffix)])
const expectedHash = createHash('sha256').update(expectedBytes).digest('hex')
if (!completedAsset
  || completedIntake?.state !== 'uploaded'
  || completedIntake.intended_matter_id !== null
  || completedReservation?.state !== 'consumed'
  || completedReceipt?.code !== 'ok'
  || completedAsset.bucket_id !== 'documents'
  || completedAsset.byte_size !== expectedBytes.byteLength
  || completedAsset.sha256 !== expectedHash
  || completedAsset.detected_mime_type !== 'application/pdf'
  || completedAsset.availability !== 'available') {
  throw new Error('The completed TUS upload does not have authoritative finalized lineage.')
}
const { data: completedObject, error: completedObjectError } = await supabase.storage
  .from(completedAsset.bucket_id)
  .download(completedAsset.object_key)
if (completedObjectError || !completedObject) throw new Error('The finalized browser upload object is missing from private Storage.')
const completedObjectBytes = Buffer.from(await completedObject.arrayBuffer())
if (createHash('sha256').update(completedObjectBytes).digest('hex') !== expectedHash) {
  throw new Error('The finalized browser upload bytes do not match the selected synthetic PDF.')
}

for (const session of cancelled) {
  const intake = intakes.find(item => item.upload_session_id === session.id)
  const asset = assets.find(item => item.id === session.asset_id)
  const reservation = reservations.find(item => item.upload_session_id === session.id)
  const receipt = receipts.find(item => item.upload_session_id === session.id && item.command === 'cancel')
  if (!asset
    || intake?.state !== 'discarded'
    || intake.failure_code !== 'upload_cancelled'
    || intake.intended_matter_id !== 'd0020000-0000-4000-8000-000000000001'
    || reservation?.state !== 'released'
    || receipt?.code !== 'cancelled'
    || asset.availability !== 'failed'
    || asset.failure_code !== 'upload_cancelled'
    || asset.byte_size !== 52_428_800) {
    throw new Error('A cancelled TUS upload does not have authoritative terminal lineage.')
  }
  const { data: cancelledObject, error: cancelledObjectError } = await supabase.storage
    .from(asset.bucket_id)
    .download(asset.object_key)
  if (cancelledObject || cancelledObjectError?.statusCode !== '404') {
    throw new Error('A cancelled in-flight browser upload did not resolve to an absent private Storage object.')
  }
}

const { data: sharedAsset, error: sharedAssetError } = await supabase
  .from('file_assets')
  .select('bucket_id, object_key, byte_size, sha256, availability')
  .eq('id', sharedAssetId)
  .eq('org_id', orgId)
  .single()
if (sharedAssetError
  || sharedAsset.availability !== 'available'
  || sharedAsset.byte_size !== sourcePdf.byteLength + Buffer.byteLength(sharedSuffix)
  || sharedAsset.sha256 !== createHash('sha256')
    .update(Buffer.concat([sourcePdf, Buffer.from(sharedSuffix)]))
    .digest('hex')) {
  throw new Error('The shared Intake asset lost its canonical private Storage authority.')
}
const { data: sharedObject, error: sharedObjectError } = await supabase.storage
  .from(sharedAsset.bucket_id)
  .download(sharedAsset.object_key)
if (sharedObjectError || !sharedObject) throw new Error('The shared Intake object is missing from private Storage.')
const sharedObjectBytes = Buffer.from(await sharedObject.arrayBuffer())
if (createHash('sha256').update(sharedObjectBytes).digest('hex') !== sharedAsset.sha256) {
  throw new Error('The shared Intake Storage bytes do not match the canonical asset hash.')
}

process.stdout.write('Verified one finalized TUS upload, two same-file cancelled sessions, and the shared Intake source in local database and private Storage.\n')
