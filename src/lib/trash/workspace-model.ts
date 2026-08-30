export type TrashResourceType = 'client' | 'matter' | 'document'
export type TrashResourceFilter = 'all' | TrashResourceType

export type TrashWorkspaceProjectionRow = {
  row_kind: string
  total_storage_bytes: number
  operation_id: string | null
  root_resource_type: TrashResourceType | null
  root_resource_id: string | null
  root_membership_id: string | null
  root_name: string | null
  root_parent_context: string | null
  root_client_id: string | null
  root_matter_id: string | null
  root_document_id: string | null
  deleted_at: string | null
  deleted_by_name: string | null
  reason: string | null
  included_client_count: number | null
  included_matter_count: number | null
  included_document_count: number | null
  operation_storage_bytes: number | null
  member_membership_id: string | null
  member_parent_membership_id: string | null
  member_resource_type: TrashResourceType | null
  member_resource_id: string | null
  member_name: string | null
  member_client_id: string | null
  member_matter_id: string | null
  member_document_id: string | null
}

export type TrashIncludedItem = {
  membershipId: string
  parentMembershipId: string
  resourceType: TrashResourceType
  resourceId: string
  name: string
  clientId: string | null
  matterId: string | null
  documentId: string | null
  canonicalPath: string
}

export type TrashOperation = {
  id: string
  rootMembershipId: string
  resourceType: TrashResourceType
  resourceId: string
  name: string
  parentContext: string
  clientId: string | null
  matterId: string | null
  documentId: string | null
  canonicalPath: string
  deletedAt: string
  deletedBy: string
  reason: string | null
  includedClientCount: number
  includedMatterCount: number
  includedDocumentCount: number
  storageBytes: number
  includedItems: TrashIncludedItem[]
}

export type TrashWorkspaceData = {
  operations: TrashOperation[]
  selectedOperation: TrashOperation | null
  totalStorageBytes: number
  timeZone: string
}

export function canonicalTrashResourcePath(
  resourceType: TrashResourceType,
  resourceId: string,
  matterId: string | null,
) {
  if (resourceType === 'client') return `/clients/${resourceId}`
  if (resourceType === 'matter') return `/matters/${resourceId}`
  return matterId ? `/matters/${matterId}/documents/${resourceId}` : ''
}

export function shapeTrashWorkspaceRows(
  rows: TrashWorkspaceProjectionRow[],
  selectedOperationId: string | null,
): Omit<TrashWorkspaceData, 'timeZone'> {
  const totalStorageBytes = rows[0]?.total_storage_bytes ?? 0
  const byId = new Map<string, TrashOperation>()

  for (const row of rows) {
    if (
      row.row_kind !== 'operation'
      || !row.operation_id
      || !row.root_resource_type
      || !row.root_resource_id
      || !row.root_membership_id
      || !row.root_name
      || !row.root_parent_context
      || !row.deleted_at
    ) continue

    let operation = byId.get(row.operation_id)
    if (!operation) {
      operation = {
        id: row.operation_id,
        rootMembershipId: row.root_membership_id,
        resourceType: row.root_resource_type,
        resourceId: row.root_resource_id,
        name: row.root_name,
        parentContext: row.root_parent_context,
        clientId: row.root_client_id,
        matterId: row.root_matter_id,
        documentId: row.root_document_id,
        canonicalPath: canonicalTrashResourcePath(row.root_resource_type, row.root_resource_id, row.root_matter_id),
        deletedAt: row.deleted_at,
        deletedBy: row.deleted_by_name ?? 'Former team member',
        reason: row.reason,
        includedClientCount: row.included_client_count ?? 0,
        includedMatterCount: row.included_matter_count ?? 0,
        includedDocumentCount: row.included_document_count ?? 0,
        storageBytes: row.operation_storage_bytes ?? 0,
        includedItems: [],
      }
      byId.set(row.operation_id, operation)
    }

    if (
      row.member_membership_id
      && row.member_parent_membership_id
      && row.member_resource_type
      && row.member_resource_id
      && row.member_name
    ) {
      operation.includedItems.push({
        membershipId: row.member_membership_id,
        parentMembershipId: row.member_parent_membership_id,
        resourceType: row.member_resource_type,
        resourceId: row.member_resource_id,
        name: row.member_name,
        clientId: row.member_client_id,
        matterId: row.member_matter_id,
        documentId: row.member_document_id,
        canonicalPath: canonicalTrashResourcePath(row.member_resource_type, row.member_resource_id, row.member_matter_id),
      })
    }
  }

  const operations = [...byId.values()]
  return {
    operations,
    selectedOperation: selectedOperationId ? byId.get(selectedOperationId) ?? null : null,
    totalStorageBytes,
  }
}

export function describeIncludedItems(operation: TrashOperation) {
  const parts: string[] = []
  const clientDescendants = operation.resourceType === 'client'
    ? Math.max(0, operation.includedClientCount - 1)
    : operation.includedClientCount
  const matterDescendants = operation.resourceType === 'matter'
    ? Math.max(0, operation.includedMatterCount - 1)
    : operation.includedMatterCount
  const documentDescendants = operation.resourceType === 'document'
    ? Math.max(0, operation.includedDocumentCount - 1)
    : operation.includedDocumentCount

  if (clientDescendants) parts.push(`${clientDescendants} ${clientDescendants === 1 ? 'client' : 'clients'}`)
  if (matterDescendants) parts.push(`${matterDescendants} ${matterDescendants === 1 ? 'matter' : 'matters'}`)
  if (documentDescendants) parts.push(`${documentDescendants} ${documentDescendants === 1 ? 'document' : 'documents'}`)
  return parts.length ? parts.join(' · ') : 'No included items'
}
