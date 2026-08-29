import type { Database, Json } from '@/lib/supabase/database.types'

type EffectiveMetadataRow = Database['public']['Functions']['read_current_document_effective_metadata']['Returns'][number]

export type WikiContextDocument = {
  id: string
  summary: string | null
}

const winningResolutions = new Set(['automatic', 'accepted', 'corrected'])
const safeText = /^[^\u0000-\u001F\u007F]{1,1024}$/
const safeCode = /^[A-Za-z0-9][A-Za-z0-9 .,/()&+#:_-]{0,255}$/
const safeDate = /^\d{4}-\d{2}-\d{2}$/
const safeDecimal = /^(0|[1-9][0-9]{0,17})(\.[0-9]{1,6})?$/

type Field = {
  label: string
  valueType: EffectiveMetadataRow['value_type']
  validate: (value: Json) => string | null
}

function stringValue(value: Json, expression = safeText) {
  return typeof value === 'string' && expression.test(value) ? value : null
}

function dateValue(value: Json) {
  const date = stringValue(value, safeDate)
  if (!date) return null
  const parsed = new Date(`${date}T00:00:00.000Z`)
  return Number.isNaN(parsed.valueOf()) || parsed.toISOString().slice(0, 10) !== date ? null : date
}

const scalarFields: Record<string, Field> = {
  'document.type': { label: 'Type', valueType: 'code', validate: (value) => stringValue(value, safeCode) },
  'document.reference_number': { label: 'Reference number', valueType: 'text', validate: stringValue },
  'document.date': { label: 'Document date', valueType: 'date', validate: dateValue },
  'document.client_name': { label: 'Client name', valueType: 'text', validate: stringValue },
  'document.gstin': { label: 'GSTIN', valueType: 'code', validate: (value) => stringValue(value, safeCode) },
  'document.direction': { label: 'Direction', valueType: 'code', validate: (value) => stringValue(value, safeCode) },
  'document.issued_by': { label: 'Issued by', valueType: 'text', validate: stringValue },
  'financial.tax': { label: 'Tax', valueType: 'decimal', validate: (value) => stringValue(value, safeDecimal) },
  'financial.interest': { label: 'Interest', valueType: 'decimal', validate: (value) => stringValue(value, safeDecimal) },
  'financial.penalty': { label: 'Penalty', valueType: 'decimal', validate: (value) => stringValue(value, safeDecimal) },
  'financial.fee': { label: 'Fee', valueType: 'decimal', validate: (value) => stringValue(value, safeDecimal) },
  'financial.pre_deposit': { label: 'Pre-deposit', valueType: 'decimal', validate: (value) => stringValue(value, safeDecimal) },
  'financial.total_demand': { label: 'Total demand', valueType: 'decimal', validate: (value) => stringValue(value, safeDecimal) },
  'financial.amount_in_dispute': { label: 'Amount in dispute', valueType: 'decimal', validate: (value) => stringValue(value, safeDecimal) },
  'financial.amount_relief': { label: 'Amount relief', valueType: 'decimal', validate: (value) => stringValue(value, safeDecimal) },
}

const repeatedFields: Record<string, Field> = {
  'document.financial_year': { label: 'Financial years', valueType: 'code', validate: (value) => stringValue(value, safeCode) },
  'document.client_identifier': { label: 'Client identifiers', valueType: 'code', validate: (value) => stringValue(value, safeCode) },
  'document.referenced_document_number': { label: 'Referenced documents', valueType: 'text', validate: stringValue },
  'legal_reference.provision_number': { label: 'Legal references', valueType: 'code', validate: (value) => stringValue(value, safeCode) },
  'deadline.due_date': { label: 'Deadlines', valueType: 'date', validate: dateValue },
}

function valueFor(field: Field, row: EffectiveMetadataRow) {
  if (!winningResolutions.has(row.resolution) || row.value_type !== field.valueType) return null
  return field.validate(row.normalized_value)
}

/**
 * Builds a bounded, deterministic Wiki prompt context. Only allow-listed
 * current effective values are shown; malformed, cleared, rejected, duplicate,
 * or ambiguous values are deliberately omitted rather than recovered from a
 * document column or legacy JSON payload.
 */
export function formatMatterWikiEffectiveContext(
  documents: readonly WikiContextDocument[],
  rows: readonly EffectiveMetadataRow[],
) {
  const documentIds = new Set(documents.map((document) => document.id))
  const rowsByDocument = new Map<string, EffectiveMetadataRow[]>()
  const versionsByDocument = new Map<string, Set<string>>()

  for (const row of rows) {
    if (!documentIds.has(row.document_id)) continue
    const documentRows = rowsByDocument.get(row.document_id) ?? []
    documentRows.push(row)
    rowsByDocument.set(row.document_id, documentRows)
    const versions = versionsByDocument.get(row.document_id) ?? new Set<string>()
    versions.add(row.document_version_id)
    versionsByDocument.set(row.document_id, versions)
  }

  return documents.map((document) => {
    const rowsForDocument = rowsByDocument.get(document.id) ?? []
    const versionIds = versionsByDocument.get(document.id)
    const effectiveLines: string[] = []

    // The RPC is expected to return one current version. Treat any mixed
    // version response as untrusted instead of joining a replacement's values.
    if (versionIds?.size === 1) {
      for (const [fieldPath, field] of Object.entries(scalarFields)) {
        const semanticKeys = new Set<string>()
        const candidates: string[] = []
        let duplicate = false
        for (const row of rowsForDocument.filter((candidate) => candidate.field_path === fieldPath)) {
          if (semanticKeys.has(row.semantic_candidate_key)) {
            duplicate = true
            break
          }
          semanticKeys.add(row.semantic_candidate_key)
          const value = valueFor(field, row)
          if (value) candidates.push(value)
        }
        if (!duplicate && candidates.length === 1) effectiveLines.push(`${field.label}: ${candidates[0]}`)
      }

      for (const [fieldPath, field] of Object.entries(repeatedFields)) {
        const semanticKeys = new Set<string>()
        const values = new Set<string>()
        let duplicate = false
        for (const row of rowsForDocument.filter((candidate) => candidate.field_path === fieldPath)) {
          if (semanticKeys.has(row.semantic_candidate_key)) {
            duplicate = true
            break
          }
          semanticKeys.add(row.semantic_candidate_key)
          const value = valueFor(field, row)
          if (value) values.add(value)
        }
        if (!duplicate && values.size > 0) effectiveLines.push(`${field.label}: ${[...values].sort().join(', ')}`)
      }
    }

    const metadata = effectiveLines.length > 0
      ? `Effective metadata:\n${effectiveLines.map((line) => `- ${line}`).join('\n')}`
      : 'Effective metadata: No authorised effective metadata available.'
    return `Document [ID: ${document.id}]:\nSummary: ${document.summary || 'N/A'}\n${metadata}`
  }).join('\n\n')
}
