import test from 'node:test'
import assert from 'node:assert/strict'
import { TASK_SUMMARY_BATCH_SIZE, batchTaskSummaryNoteIds } from './task-summary-batching'

test('batches Notes Task summary RPC input at the database maximum without dropping note ids', () => {
  const noteIds = Array.from({ length: 1_001 }, (_, index) => `note-${index}`)
  const batches = batchTaskSummaryNoteIds(noteIds)

  assert.deepEqual(batches.map((batch) => batch.length), [TASK_SUMMARY_BATCH_SIZE, TASK_SUMMARY_BATCH_SIZE, 1])
  assert.deepEqual(batches.flat(), noteIds)
})
