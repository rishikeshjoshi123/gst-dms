import assert from 'node:assert/strict'
import test from 'node:test'

import { refineSupabaseTypes } from './refine-supabase-types.mjs'

const specs = {
  create_note_with_optional_task: ['note_id: string', 'task_id: string'],
  get_my_tasks: [
    'assignee_user_id: string',
    'client_id: string',
    'document_id: string',
    'due_date: string',
    'due_time: string',
    'due_timezone: string',
    'matter_id: string',
  ],
  get_note_task_summaries: [
    'assignee_user_id: string',
    'due_date: string',
    'due_time: string',
    'due_timezone: string',
  ],
  get_task_comments: ['reply_to_comment_id: string', 'reply_to_sequence: number'],
  get_task_detail: [
    'assignee_user_id: string',
    'client_id: string',
    'completed_at: string',
    'completed_by: string',
    'description: string',
    'document_id: string',
    'due_date: string',
    'due_time: string',
    'due_timezone: string',
    'matter_id: string',
    'origin_note_id: string',
  ],
  get_task_transition_history: [
    'from_assignee_user_id: string',
    'from_due_date: string',
    'from_due_timezone: string',
    'to_assignee_user_id: string',
    'to_due_date: string',
    'to_due_timezone: string',
  ],
  record_completed_document_extraction_provider_usage: [
    'cost_micro_usd: number',
    'pricing_version_id: string',
    'provider_usage_event_id: string',
    'quality: Database["public"]["Enums"]["provider_usage_quality"]',
  ],
  remove_case_note: [
    'document_id: string',
    'matter_id: string',
    'removed_at: string',
  ],
  transition_task: [
    'revision: number',
    'status: Database["public"]["Enums"]["task_status"]',
    'task_id: string',
  ],
}

function generatedFixture() {
  const functions = Object.entries(specs).map(([name, fields]) => [
    `      ${name}: {`,
    '        Args: never',
    '        Returns: {',
    ...fields.map((field) => `          ${field}`),
    '        }[]',
    '      }',
  ].join('\n')).join('\n')

  return `export type Database = {\n  public: {\n    Functions: {\n${functions}\n    }\n  }\n}\n`
}

test('refines every known nullable RPC result and is idempotent', () => {
  const refined = refineSupabaseTypes(generatedFixture())

  for (const fields of Object.values(specs)) {
    for (const field of fields) {
      assert.match(refined, new RegExp(`${field.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} \\| null`))
    }
  }
  assert.equal(refineSupabaseTypes(refined), refined)
})

test('fails closed when a known generated signature drifts', () => {
  const drifted = generatedFixture().replace(
    '          task_id: string',
    '          task_id: unknown',
  )

  assert.throws(
    () => refineSupabaseTypes(drifted),
    /Unexpected generated type for create_note_with_optional_task.task_id: unknown/,
  )
})

test('fails closed when a required RPC disappears', () => {
  const missing = generatedFixture().replace(
    /      transition_task: \{[\s\S]*?      \}\n/,
    '',
  )

  assert.throws(
    () => refineSupabaseTypes(missing),
    /Expected exactly one generated RPC signature for transition_task/,
  )
})
