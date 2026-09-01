export const TASK_SUMMARY_BATCH_SIZE = 500

export function batchTaskSummaryNoteIds(noteIds: string[]): string[][] {
  const batches: string[][] = []
  for (let index = 0; index < noteIds.length; index += TASK_SUMMARY_BATCH_SIZE) {
    batches.push(noteIds.slice(index, index + TASK_SUMMARY_BATCH_SIZE))
  }
  return batches
}
