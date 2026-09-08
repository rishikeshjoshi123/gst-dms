import { readFileSync, renameSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const nullableRpcFields = {
  create_client_command: {
    client_id: 'string',
    revision: 'number',
  },
  create_matter_command: {
    client_id: 'string',
    matter_id: 'string',
    revision: 'number',
  },
  create_note_with_optional_task: {
    note_id: 'string',
    task_id: 'string',
  },
  get_my_tasks: {
    assignee_user_id: 'string',
    client_id: 'string',
    document_id: 'string',
    due_date: 'string',
    due_time: 'string',
    due_timezone: 'string',
    matter_id: 'string',
  },
  get_my_team_members: {
    authorised_email: 'string',
    display_name: 'string',
    professional_title: 'string',
  },
  get_team_directory: {
    authorised_email: 'string',
    capabilities: 'string[]',
    display_name: 'string',
    is_owner: 'boolean',
    joined_at: 'string',
    membership_id: 'string',
    professional_title: 'string',
    role: 'Database["public"]["Enums"]["org_member_role"]',
    state: 'Database["public"]["Enums"]["organisation_membership_state"]',
    user_id: 'string',
  },
  get_note_task_summaries: {
    assignee_user_id: 'string',
    due_date: 'string',
    due_time: 'string',
    due_timezone: 'string',
  },
  get_task_comments: {
    reply_to_comment_id: 'string',
    reply_to_sequence: 'number',
  },
  get_task_detail: {
    assignee_user_id: 'string',
    client_id: 'string',
    completed_at: 'string',
    completed_by: 'string',
    description: 'string',
    document_id: 'string',
    due_date: 'string',
    due_time: 'string',
    due_timezone: 'string',
    matter_id: 'string',
    origin_note_id: 'string',
  },
  get_task_transition_history: {
    from_assignee_user_id: 'string',
    from_due_date: 'string',
    from_due_timezone: 'string',
    to_assignee_user_id: 'string',
    to_due_date: 'string',
    to_due_timezone: 'string',
  },
  record_completed_document_extraction_provider_usage: {
    cost_micro_usd: 'number',
    pricing_version_id: 'string',
    provider_usage_event_id: 'string',
    quality: 'Database["public"]["Enums"]["provider_usage_quality"]',
  },
  remove_case_note: {
    document_id: 'string',
    matter_id: 'string',
    removed_at: 'string',
  },
  transition_task: {
    revision: 'number',
    status: 'Database["public"]["Enums"]["task_status"]',
    task_id: 'string',
  },
  update_client_command: {
    client_id: 'string',
    revision: 'number',
  },
  update_matter_command: {
    client_id: 'string',
    matter_id: 'string',
    revision: 'number',
  },
}

const nullableRpcArguments = {
  read_matter_timeline_chronology: {
    'p_selected_document_id?': 'string',
  },
  get_team_directory: {
    'p_query?': 'string',
    'p_role?': 'string',
    'p_state?': 'string',
  },
}

function functionBlock(source, functionName) {
  const startMarker = `      ${functionName}:`
  const start = source.indexOf(startMarker)
  if (start === -1 || source.indexOf(startMarker, start + 1) !== -1) {
    throw new Error(`Expected exactly one generated RPC signature for ${functionName}`)
  }

  const next = source.slice(start + startMarker.length).search(/^      [a-z0-9_]+:/m)
  const end = next === -1 ? source.length : start + startMarker.length + next
  return { start, end, value: source.slice(start, end) }
}

function objectBlock(source, marker, fromIndex = 0) {
  const start = source.indexOf(marker, fromIndex)
  if (start === -1 || source.indexOf(marker, start + 1) !== -1) {
    throw new Error(`Expected exactly one generated object block for ${marker.trim()}`)
  }

  const openBrace = start + marker.length - 1
  let depth = 0
  let quoted = false
  let escaped = false
  for (let index = openBrace; index < source.length; index += 1) {
    const character = source[index]
    if (quoted) {
      if (!escaped && character === '"') quoted = false
      escaped = !escaped && character === '\\'
      continue
    }
    if (character === '"') {
      quoted = true
      continue
    }
    if (character === '{') depth += 1
    if (character === '}') depth -= 1
    if (depth === 0) {
      return { start, end: index + 1, value: source.slice(start, index + 1) }
    }
  }

  throw new Error(`Unclosed generated object block for ${marker.trim()}`)
}

function normalizeEnumBlock(source, containerMarker) {
  const container = objectBlock(source, containerMarker)
  const publicSchema = objectBlock(container.value, '  public: {')
  const enums = objectBlock(publicSchema.value, '    Enums: {')
  const body = enums.value.slice('    Enums: {'.length, -1)
  const suffixMatch = body.match(/\n {4}$/)
  const suffix = suffixMatch ? suffixMatch[0] : ''
  const entriesBody = suffix ? body.slice(0, -suffix.length) : body
  const entries = [...entriesBody.matchAll(/^ {6}([a-z][a-z0-9_]*):/gm)]

  if (entries.length === 0) {
    throw new Error(`Expected generated enum entries in ${containerMarker.trim()}`)
  }

  const prefix = entriesBody.slice(0, entries[0].index)
  const blocks = entries.map((entry, index) => ({
    name: entry[1],
    value: entriesBody.slice(entry.index, entries[index + 1]?.index),
  }))
  const normalized = `${prefix}${blocks
    .sort((left, right) => (left.name < right.name ? -1 : left.name > right.name ? 1 : 0))
    .map(({ value }) => value.trimEnd())
    .join('\n')}${suffix}`
  const refinedEnums = `${enums.value.slice(0, '    Enums: {'.length)}${normalized}}`
  const refinedPublicSchema = `${publicSchema.value.slice(0, enums.start)}${refinedEnums}${publicSchema.value.slice(enums.end)}`
  const refinedContainer = `${container.value.slice(0, publicSchema.start)}${refinedPublicSchema}${container.value.slice(publicSchema.end)}`

  return `${source.slice(0, container.start)}${refinedContainer}${source.slice(container.end)}`
}

export function refineSupabaseTypes(source) {
  if (!source.includes('export type Database = {')) {
    throw new Error('Input does not look like generated Supabase database types')
  }

  let refined = source
  for (const [functionName, fields] of Object.entries(nullableRpcFields)) {
    const block = functionBlock(refined, functionName)
    let value = block.value

    if (!value.includes('        Returns: {')) {
      throw new Error(`Generated RPC ${functionName} no longer has a row return shape`)
    }

    for (const [fieldName, baseType] of Object.entries(fields)) {
      const marker = `${fieldName}: `
      let matches = 0
      value = value.split('\n').map((line) => {
        const trimmed = line.trimStart()
        if (!trimmed.startsWith(marker)) return line
        matches += 1
        const indentation = line.slice(0, line.length - trimmed.length)
        const actualType = trimmed.slice(marker.length)
        const nullableType = `${baseType} | null`
        if (actualType !== baseType && actualType !== nullableType) {
          throw new Error(
            `Unexpected generated type for ${functionName}.${fieldName}: ${actualType}`,
          )
        }
        return `${indentation}${marker}${nullableType}`
      }).join('\n')
      if (matches === 0) {
        throw new Error(`Expected at least one ${functionName}.${fieldName} result field`)
      }
    }

    refined = `${refined.slice(0, block.start)}${value}${refined.slice(block.end)}`
  }

  for (const [functionName, fields] of Object.entries(nullableRpcArguments)) {
    const block = functionBlock(refined, functionName)
    let value = block.value

    for (const [fieldName, baseType] of Object.entries(fields)) {
      const marker = `${fieldName}: `
      let matches = 0
      value = value.split('\n').map((line) => {
        const trimmed = line.trimStart()
        if (!trimmed.startsWith(marker)) return line
        matches += 1
        const indentation = line.slice(0, line.length - trimmed.length)
        const actualType = trimmed.slice(marker.length)
        const nullableType = `${baseType} | null`
        if (actualType !== baseType && actualType !== nullableType) {
          throw new Error(
            `Unexpected generated type for ${functionName}.${fieldName}: ${actualType}`,
          )
        }
        return `${indentation}${marker}${nullableType}`
      }).join('\n')
      if (matches === 0) {
        throw new Error(`Expected at least one ${functionName}.${fieldName} argument field`)
      }
    }

    refined = `${refined.slice(0, block.start)}${value}${refined.slice(block.end)}`
  }

  refined = normalizeEnumBlock(refined, 'export type Database = {')
  refined = normalizeEnumBlock(refined, 'export const Constants = {')

  return `${refined.replace(/\s+$/, '')}\n`
}

function main() {
  const inputPath = process.argv[2]
  if (!inputPath) {
    throw new Error('Usage: node scripts/refine-supabase-types.mjs <database.types.ts>')
  }

  const resolvedPath = path.resolve(process.cwd(), inputPath)
  const refined = refineSupabaseTypes(readFileSync(resolvedPath, 'utf8'))
  const temporaryPath = `${resolvedPath}.refined-${process.pid}`
  writeFileSync(temporaryPath, refined)
  renameSync(temporaryPath, resolvedPath)
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main()
}
