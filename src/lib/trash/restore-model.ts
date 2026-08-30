export type TrashRestorePreflight = {
  status: 'ready' | 'restore_blocked' | 'purge_scheduled' | 'not_allowed' | 'not_available'
  canRestore: boolean
  blockerCode: string | null
  blockingOperationId: string | null
}

export function restoreBlockerMessage(preflight: TrashRestorePreflight) {
  switch (preflight.blockerCode) {
    case 'parent_in_trash':
      return 'Restore the parent Trash group first. This item cannot return under a parent that is still in Trash.'
    case 'client_identifier_conflict':
      return 'An active client now uses the same GSTIN or PAN. An Owner or Admin must resolve that conflict before restoring this group.'
    case 'matter_identifier_conflict':
      return 'An active matter now uses the same matter code or client financial-year slot. Resolve that conflict before restoring this group.'
    case 'document_content_conflict':
      return 'The same document content is already attached to another active record. Resolve that duplicate before restoring this group.'
    case 'uniqueness_conflict':
      return 'Another active record claimed a required unique value while Restore was running. Review active records and try again with a new request.'
    case 'membership_drift':
    case 'membership_lineage_drift':
    case 'resource_state_drift':
    case 'invalid_parent':
    case 'invalid_operation':
      return 'This Trash group needs administrator review before it can be restored safely.'
    default:
      return 'This Trash group is currently blocked from restoration.'
  }
}
