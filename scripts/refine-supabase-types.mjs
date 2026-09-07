import { readFileSync, renameSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const nullableRpcFields = {
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
  transition_task: {
    revision: 'number',
    status: 'Database["public"]["Enums"]["task_status"]',
    task_id: 'string',
  },
}

function functionBlock(source, functionName) {
  const startMarker = `      ${functionName}: {`
  const start = source.indexOf(startMarker)
  if (start === -1 || source.indexOf(startMarker, start + 1) !== -1) {
    throw new Error(`Expected exactly one generated RPC signature for ${functionName}`)
  }

  const next = source.slice(start + startMarker.length).search(/^      [a-z0-9_]+: \{$/m)
  const end = next === -1 ? source.length : start + startMarker.length + next
  return { start, end, value: source.slice(start, end) }
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
      const marker = `          ${fieldName}: `
      const lines = value.split('\n').filter((line) => line.startsWith(marker))
      if (lines.length !== 1) {
        throw new Error(`Expected exactly one ${functionName}.${fieldName} result field`)
      }

      const actualType = lines[0].slice(marker.length)
      const nullableType = `${baseType} | null`
      if (actualType !== baseType && actualType !== nullableType) {
        throw new Error(
          `Unexpected generated type for ${functionName}.${fieldName}: ${actualType}`,
        )
      }
      value = value.replace(`${marker}${actualType}`, `${marker}${nullableType}`)
    }

    refined = `${refined.slice(0, block.start)}${value}${refined.slice(block.end)}`
  }

  return refined
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
