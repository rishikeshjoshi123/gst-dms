import assert from 'node:assert/strict'
import { readdir } from 'node:fs/promises'
import test from 'node:test'
import path from 'node:path'

import { conceptGroups } from './concepts'

test('the concept index lists every concept route exactly once', async () => {
  const devDirectory = path.join(process.cwd(), 'src/app/dev')
  const directoryEntries = await readdir(devDirectory, { withFileTypes: true })
  const routeDirectories = directoryEntries
    .filter((entry) => entry.isDirectory() && entry.name.endsWith('-concept'))
    .map((entry) => `/dev/${entry.name}`)
    .sort()
  const indexedRoutes = conceptGroups.flatMap((group) => group.concepts.map((concept) => concept.href)).sort()

  assert.deepEqual(indexedRoutes, routeDirectories)
  assert.equal(new Set(indexedRoutes).size, indexedRoutes.length)
})
