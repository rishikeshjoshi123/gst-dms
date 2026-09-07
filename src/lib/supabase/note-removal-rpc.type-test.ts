import type { Database } from './database.types'

type RemoveCaseNote = Database['public']['Functions']['remove_case_note']
type RemoveCaseNoteRow = RemoveCaseNote['Returns'][number]

const args: RemoveCaseNote['Args'] = { p_note_id: 'note-id' }
const moderatedArgs: RemoveCaseNote['Args'] = {
  p_note_id: 'note-id',
  p_moderation_reason: 'Required moderation reason',
}
const nullableDocumentId: string | null = null as RemoveCaseNoteRow['document_id']
const nullableMatterId: string | null = null as RemoveCaseNoteRow['matter_id']
const nullableRemovedAt: string | null = null as RemoveCaseNoteRow['removed_at']

void args
void moderatedArgs
void nullableDocumentId
void nullableMatterId
void nullableRemovedAt
