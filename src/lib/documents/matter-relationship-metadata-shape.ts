export type EffectiveMatterRelationshipDocument = {
  documentId: string
  documentVersionId: string
  docType: string | null
  referenceNumber: string | null
  referencedDocumentNumbers: string[]
}

export type RelationshipProjectionRow = {
  document_id: string
  document_version_id: string
  doc_type: string | null
  reference_number: string | null
  referenced_document_numbers: string[] | null
}

/** Pure, fail-closed shaping for the bounded relationship projection. */
export function shapeMatterRelationshipMetadata(rows: readonly RelationshipProjectionRow[]) {
  const result: EffectiveMatterRelationshipDocument[] = []
  const documentIds = new Set<string>()
  for (const row of rows) {
    if (documentIds.has(row.document_id) || !row.document_version_id) continue
    documentIds.add(row.document_id)
    result.push({
      documentId: row.document_id,
      documentVersionId: row.document_version_id,
      docType: row.doc_type,
      referenceNumber: row.reference_number,
      referencedDocumentNumbers: [...new Set(row.referenced_document_numbers ?? [])],
    })
  }
  return result
}
