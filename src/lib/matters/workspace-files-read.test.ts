import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const readerUrl = new URL('./workspace-read.ts', import.meta.url)
const callerUrl = new URL('../../components/matters/MatterActiveSection.tsx', import.meta.url)

test('active Files page combines exact count, bounded rows, identical fences, and deterministic ordering', async () => {
  const source = await readFile(readerUrl, 'utf8')
  const queryStart = source.indexOf('function activeSupportingFilesQuery')
  const queryEnd = source.indexOf('function assertSupportingFileRows', queryStart)
  const query = source.slice(queryStart, queryEnd)
  const pageStart = source.indexOf('export async function readActiveSupportingFiles')
  const pageEnd = source.indexOf('/** Validate an off-page', pageStart)
  const page = source.slice(pageStart, pageEnd)

  assert.match(query, /select\(SUPPORTING_FILE_SELECT, \{ count: 'exact' \}\)/)
  assert.match(query, /\.eq\('org_id', orgId\)[\s\S]*\.eq\('matter_id', matterId\)[\s\S]*\.eq\('document_class', 'supporting'\)[\s\S]*\.eq\('record_state', 'active'\)[\s\S]*\.is\('deleted_at', null\)/)
  assert.match(page, /\.order\('created_at', \{ ascending: false \}\)[\s\S]*\.order\('id', \{ ascending: false \}\)[\s\S]*\.range\(offset, offset \+ normalized\.limit - 1\)/)
  assert.doesNotMatch(source.slice(source.indexOf('const SUPPORTING_FILE_SELECT'), queryStart), /storage_path/)
})

test('off-page selection reuses the active page fences without expanding page items', async () => {
  const [reader, caller] = await Promise.all([readFile(readerUrl, 'utf8'), readFile(callerUrl, 'utf8')])
  const selectionStart = reader.indexOf('export async function readActiveSupportingFileSelection')
  const selectionEnd = reader.indexOf('/** Trash uses', selectionStart)
  const selection = reader.slice(selectionStart, selectionEnd)
  const filesStart = caller.indexOf('async function FilesSection')
  const filesEnd = caller.indexOf('async function CaseBriefSection', filesStart)
  const files = caller.slice(filesStart, filesEnd)

  assert.match(selection, /activeSupportingFilesQuery\(supabase, matterId, orgId, false\)[\s\S]*\.eq\('id', documentId\)[\s\S]*\.maybeSingle\(\)/)
  assert.match(files, /readActiveSupportingFiles\(matterId, route\.filesPage\)/)
  assert.match(files, /readActiveSupportingFileSelection\(matterId, route\.selectedDocumentId\)/)
  assert.ok(files.indexOf('readActiveSupportingFileSelection') < files.indexOf('getDocumentInspectorMetadata([accepted.id])'))
})

test('Trash Files uses only the exact snapshot branch', async () => {
  const caller = await readFile(callerUrl, 'utf8')
  const filesStart = caller.indexOf('async function FilesSection')
  const filesEnd = caller.indexOf('async function CaseBriefSection', filesStart)
  const files = caller.slice(filesStart, filesEnd)

  assert.match(files, /readOnly\s*\? createSupportingFilesSnapshotPage\(exactMatter\.data\.documents, route\.filesPage\)\s*:\s*await readActiveSupportingFiles/)
  assert.match(files, /readOnly\s*\? acceptedSectionSelection\([\s\S]*exactMatter\.data\.documents/)
})
