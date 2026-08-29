export type NotificationIdentity = {
  type?: string | null
  entity_type?: string | null
}

export function isRetiredStagedNotification(notification: NotificationIdentity): boolean {
  return notification.type === 'staged_doc_ready' || notification.entity_type === 'staged_document'
}

export const RETIRED_STAGED_NOTIFICATION_COPY = {
  title: 'Legacy staging record retired',
  body: 'This historical notification is retained for audit. No action is available.',
} as const
