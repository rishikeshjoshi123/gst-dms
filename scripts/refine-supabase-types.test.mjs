import assert from 'node:assert/strict'
import test from 'node:test'

import { refineSupabaseTypes } from './refine-supabase-types.mjs'

const specs = {
  create_client_command: ['client_id: string', 'revision: number'],
  create_matter_command: ['client_id: string', 'matter_id: string', 'revision: number'],
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
  get_my_team_members: [
    'authorised_email: string',
    'display_name: string',
    'professional_title: string',
  ],
  get_team_directory: [
    'authorised_email: string',
    'capabilities: string[]',
    'display_name: string',
    'is_owner: boolean',
    'joined_at: string',
    'membership_id: string',
    'professional_title: string',
    'role: Database["public"]["Enums"]["org_member_role"]',
    'state: Database["public"]["Enums"]["organisation_membership_state"]',
    'user_id: string',
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
  update_client_command: ['client_id: string', 'revision: number'],
  update_matter_command: ['client_id: string', 'matter_id: string', 'revision: number'],
}

const enumValues = {
  alpha_type: ['first', 'second'],
  membership_departure_case_state: ['active', 'withdrawn', 'offboarding_started'],
  note_template_type: ['hearing_note', 'general'],
}

function generatedFixture({ enumOrder = Object.keys(enumValues), trailing = '\n' } = {}) {
  const functions = Object.entries(specs).map(([name, fields]) => [
    `      ${name}: {`,
    '        Args: never',
    '        Returns: {',
    ...fields.map((field) => `          ${field}`),
    '        }[]',
    '      }',
  ].join('\n')).join('\n')

  const typeEnums = enumOrder.map((name) => [
    `      ${name}:`,
    ...enumValues[name].map((value) => `        | "${value}"`),
  ].join('\n')).join('\n')
  const constantEnums = enumOrder.map((name) => [
    `      ${name}: [`,
    ...enumValues[name].map((value) => `        "${value}",`),
    '      ],',
  ].join('\n')).join('\n')

  return `export type Database = {\n  public: {\n    Functions: {\n${functions}\n    }\n    Enums: {\n${typeEnums}\n    }\n  }\n}\n\nexport const Constants = {\n  public: {\n    Enums: {\n${constantEnums}\n    },\n  },\n} as const${trailing}`
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

test('canonicalizes equivalent generated enum layouts and final newlines', () => {
  const first = generatedFixture({
    enumOrder: ['note_template_type', 'membership_departure_case_state', 'alpha_type'],
    trailing: '\n\n',
  })
  const second = generatedFixture({
    enumOrder: ['membership_departure_case_state', 'alpha_type', 'note_template_type'],
    trailing: '',
  })

  const refined = refineSupabaseTypes(first)
  assert.equal(refined, refineSupabaseTypes(second))
  assert.match(refined, /Enums: \{\n      alpha_type:[\s\S]*?      membership_departure_case_state:[\s\S]*?      note_template_type:/)
  assert.match(refined, /alpha_type: \[[\s\S]*?membership_departure_case_state: \[[\s\S]*?note_template_type: \[/)
  assert.match(refined, /membership_departure_case_state:\n        \| "active"\n        \| "withdrawn"\n        \| "offboarding_started"/)
  assert.match(refined, /membership_departure_case_state: \[\n        "active",\n        "withdrawn",\n        "offboarding_started",/)
  assert.equal(refined.endsWith('\n\n'), false)
  assert.equal(refined.endsWith('\n'), true)
})
