import assert from 'node:assert/strict'
import test from 'node:test'

import {
  MATTER_FILES_DEFAULT_LIMIT,
  MATTER_FILES_MAX_LIMIT,
  MATTER_FILES_MAX_OFFSET,
  clampMatterFilesOffset,
  compareSupportingFilesNewestFirst,
  isActiveSupportingFileCandidate,
  matterFilesVisibleRange,
  normalizeMatterFilesPage,
  paginateMatterFiles,
} from './workspace-files-page'

function rows(count: number) {
  return Array.from({ length: count }, (_, index) => ({ id: `file-${index + 1}` }))
}

test('normalizes invalid and caller-controlled overflow offset and limit values', () => {
  assert.deepEqual(normalizeMatterFilesPage(), { offset: 0, limit: MATTER_FILES_DEFAULT_LIMIT })
  assert.deepEqual(normalizeMatterFilesPage({ offset: -1, limit: 0 }), { offset: 0, limit: MATTER_FILES_DEFAULT_LIMIT })
  assert.deepEqual(normalizeMatterFilesPage({ offset: ' 50', limit: '1.5' }), { offset: 0, limit: MATTER_FILES_DEFAULT_LIMIT })
  assert.deepEqual(normalizeMatterFilesPage({ offset: Number.MAX_SAFE_INTEGER, limit: 250 }), {
    offset: MATTER_FILES_MAX_OFFSET,
    limit: MATTER_FILES_MAX_LIMIT,
  })
  assert.deepEqual(normalizeMatterFilesPage({ offset: '100', limit: '25' }), { offset: 100, limit: 25 })
})

test('returns exact totals and bounded page rows for 0, 1, 50, 100, and 250 logical files', () => {
  for (const total of [0, 1, 50, 100, 250]) {
    const page = paginateMatterFiles(rows(total))
    assert.equal(page.total, total)
    assert.equal(page.items.length, Math.min(total, MATTER_FILES_DEFAULT_LIMIT))
    assert.equal(page.offset, 0)
    assert.equal(page.limit, MATTER_FILES_DEFAULT_LIMIT)
    assert.deepEqual(matterFilesVisibleRange(page), total === 0
      ? { start: 0, end: 0 }
      : { start: 1, end: Math.min(total, MATTER_FILES_DEFAULT_LIMIT) })
  }

  const last = paginateMatterFiles(rows(250), { offset: 200, limit: 50 })
  assert.equal(last.total, 250)
  assert.equal(last.items.length, 50)
  assert.deepEqual(matterFilesVisibleRange(last), { start: 201, end: 250 })
})

test('clamps obsolete page offsets after deletes and retains a valid boundary after inserts', () => {
  assert.equal(clampMatterFilesOffset(100, 50, 100), 50)
  assert.equal(clampMatterFilesOffset(100, 50, 101), 100)
  assert.equal(clampMatterFilesOffset(50, 50, 101), 50)
  assert.equal(clampMatterFilesOffset(50, 50, 0), 0)

  const afterDelete = paginateMatterFiles(rows(100), { offset: 100, limit: 50 })
  assert.deepEqual({ offset: afterDelete.offset, count: afterDelete.items.length }, { offset: 50, count: 50 })
  const afterInsert = paginateMatterFiles(rows(101), { offset: 50, limit: 50 })
  assert.deepEqual(matterFilesVisibleRange(afterInsert), { start: 51, end: 100 })
})

test('denies cross-org, cross-matter, wrong-class, deleted, trashed, and wrong selected IDs', () => {
  const base = {
    id: 'file-a',
    org_id: 'org-a',
    matter_id: 'matter-a',
    document_class: 'supporting',
    record_state: 'active',
    deleted_at: null,
  }
  const scope = { orgId: 'org-a', matterId: 'matter-a', selectedId: 'file-a' }
  assert.equal(isActiveSupportingFileCandidate(base, scope), true)
  assert.equal(isActiveSupportingFileCandidate({ ...base, org_id: 'org-b' }, scope), false)
  assert.equal(isActiveSupportingFileCandidate({ ...base, matter_id: 'matter-b' }, scope), false)
  assert.equal(isActiveSupportingFileCandidate({ ...base, document_class: 'proceeding' }, scope), false)
  assert.equal(isActiveSupportingFileCandidate({ ...base, deleted_at: '2026-09-08T00:00:00Z' }, scope), false)
  assert.equal(isActiveSupportingFileCandidate({ ...base, record_state: 'trash' }, scope), false)
  assert.equal(isActiveSupportingFileCandidate(base, { ...scope, selectedId: 'file-b' }), false)
})

test('newest-first ordering uses descending stable ID as the deterministic tie-breaker', () => {
  const sorted = [
    { id: 'file-a', created_at: '2026-09-07T00:00:00Z' },
    { id: 'file-b', created_at: '2026-09-08T00:00:00Z' },
    { id: 'file-c', created_at: '2026-09-08T00:00:00Z' },
  ].sort(compareSupportingFilesNewestFirst)
  assert.deepEqual(sorted.map(({ id }) => id), ['file-c', 'file-b', 'file-a'])
})
