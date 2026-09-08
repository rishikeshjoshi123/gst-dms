export class TaskReaderError extends Error {
  readonly code = 'task_reader_unavailable'

  constructor() {
    super('Task data is temporarily unavailable.')
  }
}
