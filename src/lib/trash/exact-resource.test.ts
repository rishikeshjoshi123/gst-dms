import assert from 'node:assert/strict'
import test from 'node:test'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const root = process.cwd()

function exportedFunction(source: string, name: string): string {
  const start = source.indexOf(`export async function ${name}`)
  assert.notEqual(start, -1, `${name} should be an exported reader`)
  const nextExport = source.indexOf('\nexport ', start + 1)
  return source.slice(start, nextExport === -1 ? undefined : nextExport)
}

function assertActiveResourceReader(source: string, name: string, expectedQueries = 1) {
  const reader = exportedFunction(source, name)
  const statePredicates = reader.match(/\.eq\('record_state', 'active'\)[\s\S]*?\.is\('deleted_at', null\)/g) ?? []
  assert.equal(statePredicates.length, expectedQueries, `${name} should keep each resource query active-only`)
}

test('exact-resource reader uses the authenticated Trash projection and document lineage binding', async () => {
  const source = await readFile(path.join(root, 'src/lib/trash/exact-resource.ts'), 'utf8')

  assert.match(source, /import 'server-only'/)
  assert.match(source, /get_exact_trashed_resource_projection/)
  assert.match(source, /\.eq\('matter_id', matterId\)[\s\S]*\.eq\('org_id', orgId\)/)
  assert.match(source, /p_expected_matter_id: expectedMatterId/)
  assert.match(source, /if \(error \|\| !projection/)
  assert.match(source, /canRestore: row\.can_restore/)
  assert.match(source, /data: \{[\s\S]*record: projection\.resource_record/)
  assert.match(source, /operationState: row\.operation_state/)
  assert.match(source, /purgeScheduledAt: row\.purge_scheduled_at/)
  assert.doesNotMatch(source, /createServiceClient/)
})

test('active collection and search readers require typed active state and legacy compatibility', async () => {
  const [clients, matters, documents, search, dashboard, notes] = await Promise.all([
    readFile(path.join(root, 'src/lib/actions/client.ts'), 'utf8'),
    readFile(path.join(root, 'src/lib/actions/matter.ts'), 'utf8'),
    readFile(path.join(root, 'src/lib/actions/document.ts'), 'utf8'),
    readFile(path.join(root, 'src/lib/actions/search.ts'), 'utf8'),
    readFile(path.join(root, 'src/app/(app)/dashboard/page.tsx'), 'utf8'),
    readFile(path.join(root, 'src/lib/actions/notes.ts'), 'utf8'),
  ])

  assertActiveResourceReader(clients, 'getClients')
  assert.match(exportedFunction(clients, 'getClients'), /\.eq\('matters\.record_state', 'active'\)[\s\S]*\.is\('matters\.deleted_at', null\)/)
  assertActiveResourceReader(matters, 'getMatters')
  assertActiveResourceReader(matters, 'getMattersByClient')
  assertActiveResourceReader(documents, 'getDocumentsByMatter', 2)
  assertActiveResourceReader(documents, 'getNeedsReviewDocuments')
  assertActiveResourceReader(search, 'searchAll', 4)
  assert.match(exportedFunction(notes, 'getNotes'), /\.eq\('matters\.record_state', 'active'\)[\s\S]*\.is\('matters\.deleted_at', null\)/)
  assert.match(exportedFunction(notes, 'getNotes'), /from\('documents'\)[\s\S]*\.eq\('record_state', 'active'\)[\s\S]*readableNotes = readableNotes\.filter/)
  assert.match(dashboard, /from\('clients'\)[\s\S]*?\.eq\('record_state', 'active'\)[\s\S]*?\.is\('deleted_at', null\)/)
  assert.match(dashboard, /from\('matters'\)[\s\S]*?\.eq\('record_state', 'active'\)[\s\S]*?\.is\('deleted_at', null\)/)
  assert.match(dashboard, /from\('documents'\)[\s\S]*?\.eq\('record_state', 'active'\)[\s\S]*?\.is\('deleted_at', null\)/)
})

test('canonical exact routes reuse their familiar compositions in Trash read-only mode', async () => {
  const pages = await Promise.all([
    readFile(path.join(root, 'src/app/(app)/clients/[id]/page.tsx'), 'utf8'),
    readFile(path.join(root, 'src/app/(app)/matters/[id]/page.tsx'), 'utf8'),
    readFile(path.join(root, 'src/app/(app)/matters/[id]/documents/[docId]/page.tsx'), 'utf8'),
  ])

  for (const page of pages) {
    assert.match(page, /state === 'trash'/)
    assert.match(page, /TrashReadOnlyStrip/)
    assert.doesNotMatch(page, /state !== 'active'\) notFound/)
  }
  assert.match(pages[0], /isTrashReadOnly[\s\S]*exactClient\.data\.record/)
  assert.match(pages[0], /!isTrashReadOnly[\s\S]*NewMatterButton/)
  assert.match(pages[1], /<MatterTabs[\s\S]*readOnly=\{isTrashReadOnly\}/)
  assert.match(pages[2], /<TimelineDocumentDetail[\s\S]*readOnly=\{isTrashReadOnly\}/)
})

test('Trash read-only compositions suppress realtime and direct mutation handlers', async () => {
  const sources = await Promise.all([
    readFile(path.join(root, 'src/components/matters/MatterTabs.tsx'), 'utf8'),
    readFile(path.join(root, 'src/components/matters/TimelineGraph.tsx'), 'utf8'),
    readFile(path.join(root, 'src/components/matters/TimelineDocumentDetail.tsx'), 'utf8'),
    readFile(path.join(root, 'src/components/matters/MatterDetailsTab.tsx'), 'utf8'),
    readFile(path.join(root, 'src/components/matters/MatterNotesTab.tsx'), 'utf8'),
    readFile(path.join(root, 'src/components/matters/CaseWikiTab.tsx'), 'utf8'),
    readFile(path.join(root, 'src/components/matters/TimelineGraphNode.tsx'), 'utf8'),
  ])

  assert.match(sources[0], /useEffect\(\(\) => \{[\s\S]*if \(readOnly\) return[\s\S]*supabase\.channel/)
  for (const source of sources.slice(1)) {
    assert.match(source, /readOnly/)
  }
  assert.match(sources[2], /if \(readOnly\) return/g)
  assert.match(sources[3], /if \(readOnly\) return/g)
  assert.match(sources[4], /if \(readOnly\) return/g)
  assert.match(sources[5], /if \(readOnly\) return/g)
  assert.match(sources[1], /nodesConnectable=\{!readOnly\}/)
  assert.match(sources[1], /edgesFocusable=\{!readOnly\}/)
  assert.match(sources[2], /File label/)
  assert.doesNotMatch(sources[2], />Storage Path</)
  assert.match(sources[3], /!readOnly && <button[\s\S]*\+ Add Synopsis/)
  assert.match(sources[6], /!readOnly && <Handle/g)
})

test('direct legacy commands reject trashed resource targets before mutating', async () => {
  const [clientActions, matterActions, noteActions, documentActions] = await Promise.all([
    readFile(path.join(root, 'src/lib/actions/client.ts'), 'utf8'),
    readFile(path.join(root, 'src/lib/actions/matter.ts'), 'utf8'),
    readFile(path.join(root, 'src/lib/actions/notes.ts'), 'utf8'),
    readFile(path.join(root, 'src/lib/actions/document.ts'), 'utf8'),
  ])

  assert.match(exportedFunction(clientActions, 'updateClientAction'), /\.eq\('record_state', 'active'\)[\s\S]*\.is\('deleted_at', null\)/)
  for (const command of ['createMatter', 'updateMatterDetails']) {
    assert.match(exportedFunction(matterActions, command), /\.eq\('record_state', 'active'\)[\s\S]*\.is\('deleted_at', null\)/)
  }
  for (const command of ['updateNote', 'deleteNote']) {
    assert.match(exportedFunction(noteActions, command), /from\('matters'\)[\s\S]*\.eq\('record_state', 'active'\)[\s\S]*\.is\('deleted_at', null\)/)
  }
  for (const command of ['reassignDocumentMatter', 'setDocumentClass', 'updateDocumentMetadata', 'createManualLink', 'deleteDocumentLink']) {
    assert.match(exportedFunction(documentActions, command), /\.eq\('record_state', 'active'\)[\s\S]*\.is\('deleted_at', null\)/)
  }
  assert.match(exportedFunction(matterActions, 'setMatterStatus'), /\.eq\('record_state', 'active'\)[\s\S]*\.is\('deleted_at', null\)/)
  assert.match(exportedFunction(documentActions, 'dismissReviewFlag'), /\.eq\('record_state', 'active'\)[\s\S]*\.is\('deleted_at', null\)/)
})

test('SQL projections expose allowlisted UI data and keep purge-scheduled Back to Trash valid', async () => {
  const [projection, workspaceMigration, strip] = await Promise.all([
    readFile(path.join(root, 'supabase/migrations/00086_exact_trashed_resource_projection.sql'), 'utf8'),
    readFile(path.join(root, 'supabase/migrations/00087_trash_workspace_purge_scheduled_visibility.sql'), 'utf8'),
    readFile(path.join(root, 'src/components/trash/TrashReadOnlyStrip.tsx'), 'utf8'),
  ])

  assert.doesNotMatch(projection, /to_jsonb\(selected_document\)|to_jsonb\(document\)/)
  assert.doesNotMatch(projection, /'storage_path'|'raw_metadata'|'content_hash'|'embedding'|'search_vector'/)
  assert.match(projection, /'documents', CASE WHEN note_document\.id IS NULL/)
  assert.match(projection, /note\.document_id = ANY\(projected_document_ids\)/)
  assert.match(workspaceMigration, /'purge_scheduled'::public\.trash_operation_state/)
  assert.match(strip, /operationState === 'purge_scheduled'/)
  assert.match(strip, /href=\{`\/trash\?selected=/)
})
