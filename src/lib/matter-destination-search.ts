export const MATTER_DESTINATION_RESULT_LIMIT = 20
export const MATTER_DESTINATION_INCLUDE_LIMIT = 60
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export type MatterDestinationSearchOptions = {
  query?: string
  includeIds?: string[]
}

export function normalizeMatterDestinationSearch(options: MatterDestinationSearchOptions = {}) {
  const query = options.query?.trim().replace(/\s+/g, ' ').slice(0, 100) ?? ''
  const includeIds = Array.from(new Set(options.includeIds ?? []))
    .filter((id) => UUID_PATTERN.test(id))
    .slice(0, MATTER_DESTINATION_INCLUDE_LIMIT)

  return { query, includeIds }
}

export function escapeMatterDestinationLike(value: string) {
  return value.replace(/[\\%_]/g, (character) => `\\${character}`)
}
