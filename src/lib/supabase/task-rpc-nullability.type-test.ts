import type { Database } from './database.types'

type Assert<T extends true> = T
type IsNullable<T> = null extends T ? true : false

type List = Database['public']['Functions']['get_my_tasks']['Returns'][number]
type Summary = Database['public']['Functions']['get_note_task_summaries']['Returns'][number]
type Detail = Database['public']['Functions']['get_task_detail']['Returns'][number]
type History = Database['public']['Functions']['get_task_transition_history']['Returns'][number]
type CreateNoteWithOptionalTask = Database['public']['Functions']['create_note_with_optional_task']['Returns'][number]
type Transition = Database['public']['Functions']['transition_task']['Returns'][number]

type _ListNullability = Assert<
  IsNullable<List['assignee_user_id']> &
  IsNullable<List['client_id']> &
  IsNullable<List['document_id']> &
  IsNullable<List['due_date']> &
  IsNullable<List['due_time']> &
  IsNullable<List['due_timezone']> &
  IsNullable<List['matter_id']>
>
type _SummaryNullability = Assert<
  IsNullable<Summary['assignee_user_id']> &
  IsNullable<Summary['due_date']> &
  IsNullable<Summary['due_time']> &
  IsNullable<Summary['due_timezone']>
>
type _DetailNullability = Assert<
  IsNullable<Detail['assignee_user_id']> &
  IsNullable<Detail['client_id']> &
  IsNullable<Detail['completed_at']> &
  IsNullable<Detail['completed_by']> &
  IsNullable<Detail['description']> &
  IsNullable<Detail['document_id']> &
  IsNullable<Detail['due_date']> &
  IsNullable<Detail['due_time']> &
  IsNullable<Detail['due_timezone']> &
  IsNullable<Detail['matter_id']> &
  IsNullable<Detail['origin_note_id']>
>
type _HistoryNullability = Assert<
  IsNullable<History['from_assignee_user_id']> &
  IsNullable<History['from_due_date']> &
  IsNullable<History['from_due_timezone']> &
  IsNullable<History['to_assignee_user_id']> &
  IsNullable<History['to_due_date']> &
  IsNullable<History['to_due_timezone']>
>
type _CreateNoteWithOptionalTaskNullability = Assert<
  IsNullable<CreateNoteWithOptionalTask['note_id']> &
  IsNullable<CreateNoteWithOptionalTask['task_id']>
>
type _TransitionNullability = Assert<
  IsNullable<Transition['task_id']> &
  IsNullable<Transition['revision']> &
  IsNullable<Transition['status']>
>

export const taskRpcNullabilityTypeProof: [
  _ListNullability,
  _SummaryNullability,
  _DetailNullability,
  _HistoryNullability,
  _CreateNoteWithOptionalTaskNullability,
  _TransitionNullability,
] = [true, true, true, true, true, true]
