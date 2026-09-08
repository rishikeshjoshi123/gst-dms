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
    'reassignDocumentMatter',
    'dismissReviewFlag',
    'setDocumentClass',
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

test('legacy document copy fails before storage or direct document insertion', () => {
  const source = readFileSync(new URL('./document.ts', import.meta.url), 'utf8')
  const reassign = exportedFunction(source, 'reassignDocumentMatter')
  const copyGuard = reassign.indexOf("if (mode === 'copy')")
  const clientCreation = reassign.indexOf('createClient()')

  assert.ok(copyGuard >= 0 && copyGuard < clientCreation)
  assert.doesNotMatch(reassign, /\.from\('documents'\)\s*\.insert/)
  assert.doesNotMatch(reassign, /\.storage\s*\.from\('documents'\)\s*\.upload/)
})

test('legacy metadata editing fails before client creation or direct document update', () => {
  const source = readFileSync(new URL('./document.ts', import.meta.url), 'utf8')
  const metadataUpdate = exportedFunction(source, 'updateDocumentMetadata')

  assert.doesNotMatch(metadataUpdate, /createClient\(\)/)
  assert.doesNotMatch(metadataUpdate, /\.from\('documents'\)\s*\.update/)
  assert.match(metadataUpdate, /governed inspector correction workflow/)
})

test('chaining review mutations invalidate the exact document whose status and reason changed', () => {
  const source = readFileSync(new URL('./chaining.ts', import.meta.url), 'utf8')

  assert.equal((source.match(/\.select\('id'\)\.maybeSingle\(\)/g) ?? []).length, 2)
  assert.equal((source.match(/revalidatePath\(canonicalDocumentPath\(reviewedDocument\.id\)\)/g) ?? []).length, 2)
})

test('link cleanup invalidates every captured endpoint for move and demotion', () => {
  const source = readFileSync(new URL('./document.ts', import.meta.url), 'utf8')
  const move = exportedFunction(source, 'reassignDocumentMatter')
  const documentClass = exportedFunction(source, 'setDocumentClass')

  for (const mutation of [move, documentClass]) {
    assert.match(mutation, /select\('from_doc_id, to_doc_id'\)/)
    assert.match(mutation, /affectedLinkedDocumentIds\.add\(link\.from_doc_id\)/)
    assert.match(mutation, /if \(link\.to_doc_id\) affectedLinkedDocumentIds\.add\(link\.to_doc_id\)/)
    assert.match(mutation, /for \(const affectedDocumentId of affectedLinkedDocumentIds\)[\s\S]*revalidatePath\(canonicalDocumentPath\(affectedDocumentId\)\)/)
  }
})
