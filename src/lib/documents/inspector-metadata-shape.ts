import type { Database, Json } from '@/lib/supabase/database.types'

type EffectiveMetadataRow = Database['public']['Functions']['read_current_document_inspector_projection']['Returns'][number]

export type DocumentInspectorMetadata = {
  state: 'available' | 'unavailable'
  documentVersionId: string | null
  docType: string | null
  referenceNumber: string | null
  documentDate: string | null
  clientName: string | null
  gstin: string | null
  financialYears: string[]
  tax: string | null
  interest: string | null
  penalty: string | null
  totalDemand: string | null
  issuedBy: string | null
  direction: string | null
  fieldCandidates: Record<string, { id: string; valueType: string }>
}

const scalarFields = {
  'document.type': 'docType',
  'document.reference_number': 'referenceNumber',
  'document.date': 'documentDate',
  'document.client_name': 'clientName',
  'document.gstin': 'gstin',
  'document.issued_by': 'issuedBy',
  'document.direction': 'direction',
  'financial.tax': 'tax',
  'financial.interest': 'interest',
  'financial.penalty': 'penalty',
  'financial.total_demand': 'totalDemand',
} as const

const winningResolutions = new Set(['automatic', 'accepted', 'corrected'])
const decisionResolutions = new Set(['automatic', 'accepted', 'corrected', 'rejected', 'cleared'])

function stringValue(value: Json): string | null {
  return typeof value === 'string' && value.trim() !== '' ? value : null
}

function unavailable(): DocumentInspectorMetadata {
  return {
    state: 'unavailable', documentVersionId: null, docType: null, referenceNumber: null,
    documentDate: null, clientName: null, gstin: null, financialYears: [], tax: null,
    interest: null, penalty: null, totalDemand: null, issuedBy: null,
    direction: null, fieldCandidates: {},
  }
}

/**
 * Shapes the secured effective-metadata rows for the read-only document
 * inspector. Rejected, cleared, ambiguous, malformed, and unknown values are
 * deliberately absent: this consumer must never revive legacy JSON values.
 */
export function shapeDocumentInspectorMetadata(
  documentIds: readonly string[],
  rows: readonly EffectiveMetadataRow[],
): Record<string, DocumentInspectorMetadata> {
  const allowedIds = new Set(documentIds)
  const result = Object.fromEntries(documentIds.map((id) => [id, unavailable()])) as Record<string, DocumentInspectorMetadata>
  const fieldValues = new Map<string, Map<string, Set<string>>>()
  const versionIds = new Map<string, Set<string>>()

  for (const row of rows) {
    if (!allowedIds.has(row.document_id)) continue
    const versions = versionIds.get(row.document_id) ?? new Set<string>()
    versions.add(row.document_version_id)
    versionIds.set(row.document_id, versions)
    if (!winningResolutions.has(row.resolution)) continue
    const value = stringValue(row.normalized_value)
    if (!value) continue

    const byField = fieldValues.get(row.document_id) ?? new Map<string, Set<string>>()
    const values = byField.get(row.field_path) ?? new Set<string>()
    values.add(value)
    byField.set(row.field_path, values)
    fieldValues.set(row.document_id, byField)
  }

  for (const documentId of documentIds) {
    const versions = versionIds.get(documentId)
    const byField = fieldValues.get(documentId) ?? new Map<string, Set<string>>()
    if (!versions || versions.size !== 1) continue

    const metadata = unavailable()
    metadata.state = 'available'
    metadata.documentVersionId = [...versions][0]
    for (const [fieldPath, property] of Object.entries(scalarFields)) {
      const values = byField.get(fieldPath)
      if (values?.size === 1) metadata[property] = [...values][0]
    }
    metadata.financialYears = [...(byField.get('document.financial_year') ?? [])].sort()
    const candidatesByField = new Map<string, EffectiveMetadataRow[]>()
    for (const candidate of rows) {
      if (candidate.document_id !== documentId
        || candidate.document_version_id !== metadata.documentVersionId
        || !decisionResolutions.has(candidate.resolution)) continue
      const candidates = candidatesByField.get(candidate.field_path) ?? []
      candidates.push(candidate)
      candidatesByField.set(candidate.field_path, candidates)
    }
    for (const [fieldPath, candidates] of candidatesByField.entries()) {
      const candidateIds = new Set(candidates.map((candidate) => candidate.document_field_candidate_id))
      if (candidateIds.size === 1) {
        metadata.fieldCandidates[fieldPath] = {
          id: candidates[0].document_field_candidate_id,
          valueType: candidates[0].value_type,
        }
      }
    }
    result[documentId] = metadata
  }

  return result
}
