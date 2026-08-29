export function selectedDocumentIdentity(
  document: { display_title?: string | null; storage_path?: string | null },
  effectiveMetadata: { state: 'available' | 'unavailable'; referenceNumber: string | null },
) {
  return (effectiveMetadata.state === 'available' ? effectiveMetadata.referenceNumber : null)
    || document.display_title
    || document.storage_path?.split('/').filter(Boolean).pop()
    || 'Document (reference unavailable)'
}

export function linkedDocumentIdentity(
  document: { display_title?: string | null; storage_path?: string | null },
  effectiveMetadata: { state: 'available' | 'unavailable'; referenceNumber: string | null } | undefined,
) {
  return selectedDocumentIdentity(document, effectiveMetadata ?? { state: 'unavailable', referenceNumber: null })
}

export function linkedDocumentDate(
  document: { created_at?: string | null },
  effectiveMetadata: { state: 'available' | 'unavailable'; documentDate: string | null } | undefined,
) {
  if (effectiveMetadata?.state === 'available' && effectiveMetadata.documentDate) {
    return effectiveMetadata.documentDate
  }

  const createdAt = document.created_at ? new Date(document.created_at) : null
  return createdAt && !Number.isNaN(createdAt.getTime())
    ? createdAt.toISOString().split('T')[0]
    : 'Date unavailable'
}
