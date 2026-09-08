export function acceptedSectionSelection<
  T extends { id: string; matter_id: string; document_class: string | null },
>(
  requestedDocumentId: string | null,
  matterId: string,
  expectedClass: 'proceeding' | 'supporting',
  documents: readonly T[],
) {
  if (!requestedDocumentId) return null
  return documents.find((document) => (
    document.id === requestedDocumentId
    && document.matter_id === matterId
    && (document.document_class === expectedClass
      || (expectedClass === 'proceeding' && document.document_class === null))
  )) ?? null
}
