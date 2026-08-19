/**
 * Helper utilities for verifying the liveness of hierarchical resources.
 * 
 * In our system, soft-deletion cascades downwards (Client -> Matter -> Document).
 * However, due to race conditions with background tasks (Trigger.dev), a child resource
 * (like a Document) might be created just *after* its parent (Matter) was soft-deleted.
 * 
 * These helpers perform a defense-in-depth "hierarchical liveness check" to ensure
 * a resource and its entire ancestor chain are still alive (deleted_at IS NULL).
 */

/**
 * Checks if a document and its parent matter and client are all active.
 * Expects the query to have selected: `deleted_at, matters!inner(deleted_at, clients!inner(deleted_at))`
 */
export function isDocumentActive(doc: {
  deleted_at?: string | null
  matters?: {
    deleted_at?: string | null
    clients?: {
      deleted_at?: string | null
    }
  } | null
}): boolean {
  if (doc.deleted_at) return false
  if (doc.matters?.deleted_at) return false
  if (doc.matters?.clients?.deleted_at) return false
  return true
}

/**
 * Checks if a matter and its parent client are both active.
 * Expects the query to have selected: `deleted_at, clients!inner(deleted_at)`
 */
export function isMatterActive(matter: {
  deleted_at?: string | null
  clients?: {
    deleted_at?: string | null
  } | null
}): boolean {
  if (matter.deleted_at) return false
  if (matter.clients?.deleted_at) return false
  return true
}
