export function documentInspectorIds(
  selectedDocumentId: string,
  documents: readonly { id: string }[],
) {
  return [...new Set([selectedDocumentId, ...documents.map((document) => document.id)])]
}
