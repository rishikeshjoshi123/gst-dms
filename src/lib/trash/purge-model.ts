import type { TrashResourceType } from './workspace-model'

export type TrashPurgeBlocker = {
  code: 'legal_hold' | 'active_export' | 'active_backup' | 'platform_dependency'
  resourceType: TrashResourceType
  resourceId: string
}

export type TrashPurgeImpact = {
  code: 'ready' | 'in_progress' | 'purged'
  operationId: string
  rootResourceType: TrashResourceType
  rootResourceId: string
  rootName: string | null
  confirmationText: string | null
  clients: number
  matters: number
  documents: number
  uniqueBytes: number
  sharedBytesRetained: number
  holdCount: number
  activeExportCount: number
  blockerCount: number
  blockers: TrashPurgeBlocker[]
  canPurge: boolean
  impactFingerprint: string
  impactVersion: number
  operationState: string
  jobState: string | null
  safeErrorCode: string | null
  scheduledAt: string | null
  purgedAt: string | null
}

type ProjectionRow = Record<string, unknown>

export function shapeTrashPurgeImpact(row: ProjectionRow): TrashPurgeImpact | null {
  if (!row.operation_id || !row.root_resource_id || !row.root_resource_type || !row.impact_fingerprint) return null
  const blockers = Array.isArray(row.blockers) ? row.blockers.flatMap((item) => {
    if (!item || typeof item !== 'object') return []
    const value = item as Record<string, unknown>
    if (typeof value.code !== 'string' || typeof value.resourceType !== 'string' || typeof value.resourceId !== 'string') return []
    return [{ code: value.code, resourceType: value.resourceType, resourceId: value.resourceId } as TrashPurgeBlocker]
  }) : []
  return {
    code: String(row.code) as TrashPurgeImpact['code'],
    operationId: String(row.operation_id),
    rootResourceType: String(row.root_resource_type) as TrashResourceType,
    rootResourceId: String(row.root_resource_id),
    rootName: typeof row.root_name === 'string' ? row.root_name : null,
    confirmationText: typeof row.confirmation_text === 'string' ? row.confirmation_text : null,
    clients: Number(row.included_client_count ?? 0), matters: Number(row.included_matter_count ?? 0),
    documents: Number(row.included_document_count ?? 0), uniqueBytes: Number(row.unique_bytes ?? 0),
    sharedBytesRetained: Number(row.shared_bytes_retained ?? 0), holdCount: Number(row.hold_count ?? 0),
    activeExportCount: Number(row.active_export_count ?? 0), blockerCount: Number(row.blocker_count ?? 0),
    blockers, canPurge: row.can_purge === true, impactFingerprint: String(row.impact_fingerprint),
    impactVersion: Number(row.impact_version ?? 1), operationState: String(row.operation_state),
    jobState: typeof row.job_state === 'string' ? row.job_state : null,
    safeErrorCode: typeof row.job_safe_error_code === 'string' ? row.job_safe_error_code : null,
    scheduledAt: typeof row.scheduled_permanent_deletion_at === 'string' ? row.scheduled_permanent_deletion_at : null,
    purgedAt: typeof row.purged_at === 'string' ? row.purged_at : null,
  }
}
