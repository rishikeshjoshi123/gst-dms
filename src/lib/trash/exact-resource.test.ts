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

test('exact-resource reader keeps Trash context read-only and document lineage-bound', async () => {
  const source = await readFile(path.join(root, 'src/lib/trash/exact-resource.ts'), 'utf8')

  assert.match(source, /import 'server-only'/)
  assert.match(source, /get_exact_resource_trash_context/)
  assert.match(source, /\.eq\('matter_id', matterId\)[\s\S]*\.eq\('org_id', orgId\)/)
  assert.match(source, /p_expected_matter_id: expectedMatterId/)
  assert.match(source, /canRestore: row\.can_restore/)
  assert.match(source, /operationState: row\.operation_state/)
  assert.match(source, /purgeScheduledAt: row\.purge_scheduled_at/)
  assert.doesNotMatch(source, /createServiceClient/)
})

test('active collection and search readers require typed active state and legacy compatibility', async () => {
  const [clients, matters, documents, search, dashboard] = await Promise.all([
    readFile(path.join(root, 'src/lib/actions/client.ts'), 'utf8'),
    readFile(path.join(root, 'src/lib/actions/matter.ts'), 'utf8'),
    readFile(path.join(root, 'src/lib/actions/document.ts'), 'utf8'),
    readFile(path.join(root, 'src/lib/actions/search.ts'), 'utf8'),
    readFile(path.join(root, 'src/app/(app)/dashboard/page.tsx'), 'utf8'),
  ])

  assertActiveResourceReader(clients, 'getClients')
  assert.match(exportedFunction(clients, 'getClients'), /\.eq\('matters\.record_state', 'active'\)[\s\S]*\.is\('matters\.deleted_at', null\)/)
  assertActiveResourceReader(matters, 'getMatters')
  assertActiveResourceReader(matters, 'getMattersByClient')
  assertActiveResourceReader(documents, 'getDocumentsByMatter', 2)
  assertActiveResourceReader(documents, 'getNeedsReviewDocuments')
  assertActiveResourceReader(search, 'searchAll', 4)
  assert.match(dashboard, /from\('clients'\)[\s\S]*?\.eq\('record_state', 'active'\)[\s\S]*?\.is\('deleted_at', null\)/)
  assert.match(dashboard, /from\('matters'\)[\s\S]*?\.eq\('record_state', 'active'\)[\s\S]*?\.is\('deleted_at', null\)/)
  assert.match(dashboard, /from\('documents'\)[\s\S]*?\.eq\('record_state', 'active'\)[\s\S]*?\.is\('deleted_at', null\)/)
})

test('exact routes consume the reader but retain notFound for Trash until action suppression ships', async () => {
  const pages = await Promise.all([
    readFile(path.join(root, 'src/app/(app)/clients/[id]/page.tsx'), 'utf8'),
    readFile(path.join(root, 'src/app/(app)/matters/[id]/page.tsx'), 'utf8'),
    readFile(path.join(root, 'src/app/(app)/matters/[id]/documents/[docId]/page.tsx'), 'utf8'),
  ])

  assert.match(pages[0], /getExactClient[\s\S]*exactClient\.state !== 'active'/)
  assert.match(pages[1], /getExactMatter[\s\S]*exactMatter\.state !== 'active'/)
  assert.match(pages[2], /getExactDocument[\s\S]*exactDocument\.state !== 'active'/)
})
