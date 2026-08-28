/**
 * Temporary read-model mapping for canonical global Intake rows. Keep this
 * isolated from legacy staged-document commands so removing the adapter does
 * not alter the canonical lifecycle state machine.
 */
export function canonicalInboxStatus(state: string) {
  if (state === 'duplicate') return 'duplicate'
  if (state === 'failed') return 'failed'
  if (state === 'ready') return 'ready_for_placement'
  if (state === 'uploaded' || state === 'validating' || state === 'processing') return 'analyzing'
  return 'pending_assignment'
}

/** Keep canonical failure details actionable without exposing database codes. */
export function canonicalInboxReason(state: string, failureCode: string | null) {
  if (state === 'duplicate' || failureCode === 'duplicate') {
    return 'This PDF already exists in this organisation. It was not added again.'
  }

  switch (failureCode) {
    case 'invalid_pdf':
      return 'This file is not a valid PDF. Choose a different PDF and try again.'
    case 'file_too_large':
      return 'This PDF exceeds the organisation upload limit.'
    case 'upload_expired':
      return 'This upload expired before it could be completed. Choose the PDF again.'
    case 'storage_missing':
    case 'upload_failed':
      return 'The uploaded PDF could not be confirmed in secure storage. Choose the file again.'
    case 'validation_failed':
      return 'This PDF did not pass document validation.'
    default:
      return state === 'failed'
        ? 'This intake could not be completed. Choose the PDF again or contact support.'
        : null
  }
}

export function canonicalIntakeActions(state: string) {
  return {
    canPreview: state === 'ready',
    canAssign: state === 'ready',
    canDiscard: state === 'ready',
  }
}
