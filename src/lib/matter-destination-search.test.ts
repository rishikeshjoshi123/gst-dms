import assert from 'node:assert/strict'
import test from 'node:test'
import { readFile } from 'node:fs/promises'

import {
  MATTER_DESTINATION_INCLUDE_LIMIT,
  normalizeMatterDestinationSearch,
  escapeMatterDestinationLike,
} from './matter-destination-search'

test('normalizes destination search text and bounds explicit context ids', () => {
  const ids = Array.from({ length: MATTER_DESTINATION_INCLUDE_LIMIT + 5 }, (_, index) =>
    `0198f292-a8db-7def-8${String(index).padStart(3, '0')}-0123456789ab`,
  )
  const result = normalizeMatterDestinationSearch({
    query: `  Apex   ${'x'.repeat(120)}  `,
    includeIds: ['invalid', ...ids, ids[0]],
  })

  assert.equal(result.query.length, 100)
  assert.equal(result.includeIds.length, MATTER_DESTINATION_INCLUDE_LIMIT)
  assert.equal(result.includeIds[0], ids[0])
})

test('escapes user wildcard characters before ilike queries', () => {
  assert.equal(escapeMatterDestinationLike('50%_GST\\appeal'), '50\\%\\_GST\\\\appeal')
})

test('the live destination reader and Hub use bounded server search', async () => {
  const [reader, page, hub] = await Promise.all([
    readFile(new URL('./actions/matter.ts', import.meta.url), 'utf8'),
    readFile(new URL('../app/(app)/documents/page.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../app/(app)/documents/DocumentHubClientView.tsx', import.meta.url), 'utf8'),
  ])

  assert.match(reader, /MATTER_DESTINATION_RESULT_LIMIT/)
  assert.match(reader, /\.limit\(MATTER_DESTINATION_RESULT_LIMIT\)/)
  assert.match(reader, /clients!inner/)
  assert.match(page, /searchMatterDestinations/)
  assert.doesNotMatch(page, /getMatters/)
  assert.match(hub, /Search by client, matter, code, or financial year/)
  assert.match(hub, /placementSubjectRef\.current !== selectedDocument\.id/)
  assert.match(hub, /!result\.matters\.some\(\(matter\) => matter\.id === selectedMatterId\)/)
})
