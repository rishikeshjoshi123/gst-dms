import assert from 'node:assert/strict'
import test from 'node:test'

import { refineSupabaseTypes } from './refine-supabase-types.mjs'

const specs = {
  activate_matter_identifier: [
    'identifier_id: string',
    'identifier_revision: number',
    'matter_revision: number',
  ],
  activate_document_relationship: ['relationship_id: string', 'revision: number'],
  archive_document_relationship: ['relationship_id: string', 'revision: number'],
  create_client_command: ['client_id: string', 'revision: number'],
  create_matter_command: ['client_id: string', 'matter_id: string', 'revision: number'],
  create_note_with_optional_task: ['note_id: string', 'task_id: string'],
  correct_matter_identifier: [
    'identifier_id: string',
    'identifier_revision: number',
    'matter_revision: number',
    'previous_identifier_id: string',
  ],
  get_document_hub_intake: ['failure_code: string', 'intended_matter_id: string'],
  get_intake_item_triage_context: ['uploaded_by: string'],
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
  get_trash_workspace_retention: ['auto_purge_at: string', 'remaining_seconds: number'],
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
  revoke_matter_identifier: [
    'identifier_id: string',
    'identifier_revision: number',
    'matter_revision: number',
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
  const functions = Object.entries(specs).map(([name, fields]) => {
    const result = [
      '            Returns: {',
      ...fields.map((field) => `          ${field}`),
      '            }[]',
    ]
    if (name === 'create_matter_command') {
      return [
        `      ${name}:`,
        '        | {',
        '            Args: { legacy: true }',
        ...result,
        '          }',
        '        | {',
        '            Args: { typed: true }',
        ...result,
        '          }',
      ].join('\n')
    }
    return [
      `      ${name}: {`,
      ...(name === 'get_team_directory' ? [
        '        Args: {',
        '          p_query?: string',
        '          p_role?: string',
        '          p_state?: string',
        '        }',
      ] : ['        Args: never']),
      '        Returns: {',
      ...fields.map((field) => `          ${field}`),
      '        }[]',
      '      }',
    ].join('\n')
  }).concat([
    [
      '      resolve_extraction_conflict: {',
      '        Args: {',
      '          p_candidate_id: string',
      '        }',
      '        Returns: never',
      '      }',
    ].join('\n'),
    [
      '      read_matter_identifiers: {',
      '        Args: { p_matter_id: string }',
      '        Returns: {',
      '          source_revision: string',
      '        }[]',
      '      }',
    ].join('\n'),
    [
      '      read_matter_timeline_relationships: {',
      '        Args: {',
      '          p_matter_id: string',
      '          p_selected_document_id?: string',
      '        }',
      '        Returns: {',
      '          source_revision: string',
      '        }[]',
      '      }',
    ].join('\n'),
    [
      '      read_matter_timeline_chronology: {',
      '        Args: {',
      '          p_matter_id: string',
      '          p_selected_document_id?: string',
      '        }',
      '        Returns: never',
      '      }',
    ].join('\n'),
  ]).join('\n')

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
  const createMatterBlock = refined.slice(
    refined.indexOf('      create_matter_command:'),
    refined.indexOf('      create_note_with_optional_task:'),
  )
  assert.equal([...createMatterBlock.matchAll(/matter_id: string \| null/g)].length, 2)
  assert.match(refined, /p_selected_document_id\?: string \| null/)
  assert.match(refined, /p_candidate_id: string \| null/)
  assert.match(refined, /read_matter_timeline_relationships:[\s\S]*source_revision: string \| null/)
  assert.match(refined, /read_matter_identifiers:[\s\S]*source_revision: string \| null/)
  assert.match(refined, /p_query\?: string \| null/)
  assert.match(refined, /p_role\?: string \| null/)
  assert.match(refined, /p_state\?: string \| null/)
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
