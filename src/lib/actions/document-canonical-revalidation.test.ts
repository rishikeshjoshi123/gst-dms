import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

function exportedFunction(source: string, name: string) {
  const start = source.indexOf(`export async function ${name}(`)
  assert.notEqual(start, -1, `${name} should be exported`)
  const nextExport = source.indexOf('\nexport async function ', start + 1)
  return source.slice(start, nextExport === -1 ? undefined : nextExport)
}

test('document record mutations invalidate their canonical reader', () => {
  const source = readFileSync(new URL('./document.ts', import.meta.url), 'utf8')

  for (const name of [
    'deleteDocument',
  ]) {
    assert.match(exportedFunction(source, name), /revalidatePath\(canonicalDocumentPath\(documentId\)\)/, name)
  }

})

test('relationship mutations invalidate both canonical document readers', () => {
  const source = readFileSync(new URL('./document.ts', import.meta.url), 'utf8')
  const createLink = exportedFunction(source, 'createManualLink')
  const deleteLink = exportedFunction(source, 'deleteDocumentLink')

  assert.match(createLink, /revalidatePath\(canonicalDocumentPath\(fromDocId\)\)/)
  assert.match(createLink, /revalidatePath\(canonicalDocumentPath\(toDocId\)\)/)
  assert.match(deleteLink, /revalidatePath\(canonicalDocumentPath\(link\.from_doc_id\)\)/)
  assert.match(deleteLink, /revalidatePath\(canonicalDocumentPath\(link\.to_doc_id\)\)/)
})

test('a successful scoped reprocess request invalidates the canonical reader', () => {
  const source = readFileSync(new URL('./reprocess.ts', import.meta.url), 'utf8')
  assert.match(exportedFunction(source, 'reprocessDocument'), /scheduleDocumentOutboxWake\(\)[\s\S]*revalidatePath\(canonicalDocumentPath\(documentId\)\)/)
})

test('matter financial-year synchronization invalidates every exact updated document', () => {
  const source = readFileSync(new URL('./matter.ts', import.meta.url), 'utf8')
  const updateMatter = exportedFunction(source, 'updateMatterDetails')

  assert.match(updateMatter, /rpc\('update_matter_command'/)
  assert.match(updateMatter, /\.eq\('financial_year', payload\.financialYear\)/)
  assert.match(updateMatter, /for \(const document of updatedDocuments \?\? \[\]\)[\s\S]*revalidatePath\(canonicalDocumentPath\(document\.id\)\)/)
})

test('document move and copy require confirmation and use only the governed command', () => {
  const source = readFileSync(new URL('./document.ts', import.meta.url), 'utf8')
  const reassign = exportedFunction(source, 'reassignDocumentMatter')

  assert.match(reassign, /if \(!request.success\) return/)
  assert.match(reassign, /rpc\('execute_document_boundary_repair'/)
  assert.match(reassign, /p_expected_fingerprint/)
  assert.match(reassign, /p_idempotency_key/)
  assert.doesNotMatch(reassign, /\.from\('documents'\)\s*\.insert/)
  assert.doesNotMatch(reassign, /\.from\('documents'\)\s*\.update/)
  assert.doesNotMatch(reassign, /\.storage\s*\.from\('documents'\)\s*\.upload/)
  assert.match(reassign, /revalidatePath\(canonicalDocumentPath\(documentId\)\)/)
})

test('legacy metadata editing fails before client creation or direct document update', () => {
  const source = readFileSync(new URL('./document.ts', import.meta.url), 'utf8')
  const metadataUpdate = exportedFunction(source, 'updateDocumentMetadata')

  assert.doesNotMatch(metadataUpdate, /createClient\(\)/)
  assert.doesNotMatch(metadataUpdate, /\.from\('documents'\)\s*\.update/)
  assert.match(metadataUpdate, /governed inspector correction workflow/)
})

test('legacy review status updates are absent from document and chaining actions', () => {
  const documentSource = readFileSync(new URL('./document.ts', import.meta.url), 'utf8')
  const source = readFileSync(new URL('./chaining.ts', import.meta.url), 'utf8')
  const dismiss = exportedFunction(documentSource, 'dismissReviewFlag')

  assert.doesNotMatch(dismiss, /createClient\(\)/)
  assert.doesNotMatch(dismiss, /\.from\('documents'\)\s*\.update/)
  assert.match(dismiss, /typed Review items/)
  assert.doesNotMatch(source, /\.from\('documents'\)\.update/)
  assert.doesNotMatch(source, /status: 'needs_review'/)
})

test('legacy classification fails before client creation or destructive link changes', () => {
  const source = readFileSync(new URL('./document.ts', import.meta.url), 'utf8')
  const documentClass = exportedFunction(source, 'setDocumentClass')

  assert.doesNotMatch(documentClass, /createClient\(\)/)
  assert.doesNotMatch(documentClass, /\.from\('document_links'\)/)
  assert.doesNotMatch(documentClass, /\.from\('documents'\)\s*\.update/)
  assert.match(documentClass, /governed impact workflow/)
})
