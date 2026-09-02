import type { PageWordAnchor } from './native-pdf-pages'

export type CanonicalTableCell = {
  table_index: number
  row_index: number
  column_index: number
  row_span: number
  column_span: number
  reading_order: number
  text: string
  x: number
  y: number
  width: number
  height: number
}

export type CanonicalPage = {
  page_number: number
  text: string
  ocr_words: PageWordAnchor[] | null
  table_cells?: CanonicalTableCell[] | null
}

export type VerifiedEvidence = {
  char_start: number
  char_end: number
  token_start: number | null
  token_end: number | null
  table_cell: Pick<CanonicalTableCell, 'table_index' | 'row_index' | 'column_index'> | null
  regions: Array<{ x: number; y: number; width: number; height: number }>
}
export type SourceVerification = { ok: true; evidence: VerifiedEvidence } | { ok: false; code: 'source_page_missing' | 'quote_not_in_source' | 'value_not_in_quote' | 'value_not_in_source' | 'ambiguous_source_match' | 'invalid_identifier' | 'invalid_date' }

const GSTIN = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$/
const PAN = /^[A-Z]{5}[0-9]{4}[A-Z]$/
const GSTIN_ALPHABET = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'

function gstinChecksumValid(value: string) {
  if (!GSTIN.test(value)) return false
  let total = 0
  for (let index = 0; index < 14; index += 1) {
    const digit = GSTIN_ALPHABET.indexOf(value[index]); const product = digit * (index % 2 === 0 ? 1 : 2)
    total += Math.floor(product / 36) + (product % 36)
  }
  return GSTIN_ALPHABET[(36 - (total % 36)) % 36] === value[14]
}

function normalized(value: string, type: 'text' | 'code' | 'date' | 'decimal'): string | null {
  const input = value.trim()
  if (type === 'date') {
    return normalizedDate(input)
  }
  if (type === 'decimal') return input.replace(/[₹,\s]/gu, '').replace(/^INR/iu, '')
  return input.toUpperCase().replace(/[\s./,_-]/gu, '')
}

const MONTHS: Record<string, number> = {
  january: 1, jan: 1, february: 2, feb: 2, march: 3, mar: 3,
  april: 4, apr: 4, may: 5, june: 6, jun: 6, july: 7, jul: 7,
  august: 8, aug: 8, september: 9, sep: 9, sept: 9, october: 10,
  oct: 10, november: 11, nov: 11, december: 12, dec: 12,
}

function canonicalDate(year: string, month: string, day: string): string | null {
  const numericYear = Number(year); const numericMonth = Number(month); const numericDay = Number(day)
  if (!Number.isInteger(numericYear) || !Number.isInteger(numericMonth) || !Number.isInteger(numericDay)
    || numericYear < 1000 || numericYear > 9999 || numericMonth < 1 || numericMonth > 12 || numericDay < 1) return null
  const lastDay = new Date(Date.UTC(numericYear, numericMonth, 0)).getUTCDate()
  return numericDay <= lastDay ? `${year.padStart(4, '0')}-${month.padStart(2, '0')}-${day.padStart(2, '0')}` : null
}

/**
 * Only source formats with an explicit month ordering are accepted. Numeric
 * dates are DMY (the product's Indian-document convention); English month
 * names are inherently unambiguous in either conventional order.
 */
function normalizedDate(input: string): string | null {
  const iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(input)
  if (iso) return canonicalDate(iso[1], iso[2], iso[3])
  const dmy = /^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$/.exec(input)
  if (dmy) return canonicalDate(dmy[3], dmy[2], dmy[1])
  const dayMonth = /^(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]+)\.?[,]?\s+(\d{4})$/iu.exec(input)
  if (dayMonth) return canonicalDate(dayMonth[3], String(MONTHS[dayMonth[2].toLowerCase()] ?? 0), dayMonth[1])
  const monthDay = /^([A-Za-z]+)\.?\s+(\d{1,2})(?:st|nd|rd|th)?[,]?\s+(\d{4})$/iu.exec(input)
  if (monthDay) return canonicalDate(monthDay[3], String(MONTHS[monthDay[1].toLowerCase()] ?? 0), monthDay[2])
  return null
}

function regions(words: PageWordAnchor[] | null, start: number, end: number, text: string) {
  if (!words?.length) return { token_start: null, token_end: null, table_cell: null, regions: [] }
  let cursor = start; const matched: number[] = []
  for (let index = 0; index < words.length; index += 1) {
    const wordStart = text.indexOf(words[index].text, cursor); if (wordStart < 0) continue
    cursor = wordStart + words[index].text.length
    if (wordStart < end && cursor > start) matched.push(index)
  }
  const selected = matched.map((index) => words[index]).slice(0, 16)
  // Geometry is useful only when every selected word was deterministically
  // located inside the verified quote. Never invent a box from token order.
  if (selected.length === 0) return { token_start: null, token_end: null, table_cell: null, regions: [] }
  return { token_start: matched[0] ?? null, token_end: matched.at(-1) ?? null, table_cell: null, regions: selected.map(({ x, y, width, height }) => ({ x, y, width, height })) }
}

const SOURCE_DATE = /\b(?:\d{4}-\d{2}-\d{2}|\d{1,2}[./-]\d{1,2}[./-]\d{4}|\d{1,2}(?:st|nd|rd|th)?\s+[A-Za-z]+\.?[,]?\s+\d{4}|[A-Za-z]+\.?\s+\d{1,2}(?:st|nd|rd|th)?[,]?\s+\d{4})\b/giu

function sourceValueMatchCount(text: string, value: string, type: 'text' | 'code' | 'date' | 'decimal'): number {
  const target = normalized(value, type)
  if (!target) return 0
  if (type === 'date') {
    return [...text.matchAll(SOURCE_DATE)]
      .filter((match) => normalized(match[0], 'date') === target).length
  }
  // Candidate values are short bounded scalars. Matching each non-separator
  // source character with only supported source separators catches common
  // reference/GSTIN/amount formatting while refusing a one-digit difference.
  // Decimal boundaries deliberately include decimal/grouping marks: otherwise
  // `1000` could match the prefix of the distinct source token `1,000.50`.
  const characters = [...value.trim()].filter((character) => !/[\s./,_-]/u.test(character) && character !== '₹')
  if (characters.length === 0) return 0
  const pattern = characters.map((character) => character.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&')).join('[\\s./,_-]*')
  const boundedPattern = type === 'decimal'
    // A terminal full stop is permitted, but a decimal continuation is not.
    // The extra start guard also refuses the fractional suffix of `1.1000`.
    ? `(?<![A-Za-z0-9,])(?<![0-9]\\.)${pattern}(?![A-Za-z0-9,]|\\.[0-9])`
    : `(?<![A-Za-z0-9])${pattern}(?![A-Za-z0-9])`
  return [...text.matchAll(new RegExp(boundedPattern, 'giu'))]
    .filter((match) => normalized(match[0], type) === target).length
}

function tableCellEvidence(
  cells: CanonicalTableCell[] | null | undefined,
  quote: string,
  value: string,
  type: 'text' | 'code' | 'date' | 'decimal',
) {
  const matching = (cells ?? []).filter((cell) => {
    if (!cell.text.includes(quote)) return false
    return sourceValueMatchCount(cell.text, value, type) === 1
  })
  if (matching.length !== 1) return null
  const cell = matching[0]
  return {
    token_start: null,
    token_end: null,
    table_cell: { table_index: cell.table_index, row_index: cell.row_index, column_index: cell.column_index },
    regions: [{ x: cell.x, y: cell.y, width: cell.width, height: cell.height }],
  }
}

export function verifyCanonicalSource(page: CanonicalPage | undefined, quote: string, value: string, type: 'text' | 'code' | 'date' | 'decimal', identifier?: 'gstin' | 'gstin_or_pan'): SourceVerification {
  if (!page) return { ok: false, code: 'source_page_missing' }
  const quoteStart = page.text.indexOf(quote)
  if (quoteStart < 0) return { ok: false, code: 'quote_not_in_source' }
  const expected = normalized(value, type)
  if (!expected) return { ok: false, code: 'invalid_date' }
  if ((identifier === 'gstin' && !gstinChecksumValid(value))
    || (identifier === 'gstin_or_pan' && (GSTIN.test(value) ? !gstinChecksumValid(value) : !PAN.test(value)))) return { ok: false, code: 'invalid_identifier' }
  if (sourceValueMatchCount(quote, value, type) !== 1) return { ok: false, code: 'value_not_in_quote' }
  const locations: number[] = []; let start = page.text.indexOf(quote)
  while (start >= 0) { locations.push(start); start = page.text.indexOf(quote, start + 1) }
  const valueMatches = sourceValueMatchCount(page.text, value, type)
  const tableEvidence = tableCellEvidence(page.table_cells, quote, value, type)
  if (locations.length !== 1 || valueMatches !== 1) {
    return { ok: false, code: locations.length > 1 || valueMatches > 1 ? 'ambiguous_source_match' : 'value_not_in_source' }
  }
  const charStart = quoteStart; const charEnd = quoteStart + quote.length
  return { ok: true, evidence: { char_start: charStart, char_end: charEnd, ...(tableEvidence ?? regions(page.ocr_words, charStart, charEnd, page.text)) } }
}
