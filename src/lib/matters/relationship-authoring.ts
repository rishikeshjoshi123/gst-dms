import { z } from 'zod'

export const timelineRelationshipType = z.enum(['responds_to', 'issued_pursuant_to', 'arises_from', 'challenges', 'decides', 'modifies', 'supersedes', 'remands', 'gives_effect_to'])
const revision = z.number().int().positive().max(Number.MAX_SAFE_INTEGER)
const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
const documentOption = z.object({ id: uuid, title: z.string().min(1), referenceNumber: z.string().nullable(), lifecycleRevision: revision })
const catalogueOption = z.object({ relationshipType: timelineRelationshipType, catalogueVersion: revision, canonicalPhrase: z.string().min(2).max(80), progressionPhrase: z.string().min(2).max(80) })
export const relationshipAuthoringContextSchema = z.object({ outcome: z.literal('ok'), documents: z.array(documentOption).max(1000), relationship_types: z.array(catalogueOption).max(9), relationship_source_revision: z.string().regex(/^[0-9a-f]{32}$/) })
export type RelationshipAuthoringContext = z.infer<typeof relationshipAuthoringContextSchema>
/** A confirmed archive suppresses only that exact record version, never a newer reactivation. */
export function reconcileConfirmedRelationshipArchives<T extends { id: string; revision: number }>(relationships: readonly T[], confirmed: Readonly<Record<string, number>>): T[] {
  return relationships.filter((relationship) => confirmed[relationship.id] === undefined || relationship.revision > confirmed[relationship.id])
}
export function canAddTimelineRelationship(context: RelationshipAuthoringContext | null | undefined): boolean {
  return Boolean(context && context.documents.length >= 2 && context.relationship_types.length > 0)
}
export function proceedingIdentity(document: { id: string; referenceNumber?: string | null }): string {
  return document.referenceNumber?.trim() ? `Reference: ${document.referenceNumber.trim()}` : `Record ID: …${document.id.slice(-12)}`
}
const reason = z.string().trim().max(500).refine((value) => !/[\u0000-\u001f\u007f]/.test(value), 'Use plain text for the reason.')
export const activateRelationshipSchema = z.object({ matterId: uuid, sourceId: uuid, targetId: uuid, relationshipType: timelineRelationshipType, sourceRevision: revision, targetRevision: revision, reason, idempotencyKey: uuid }).refine((value) => value.sourceId !== value.targetId)
export const archiveRelationshipSchema = z.object({ matterId: uuid, relationshipId: uuid, revision, reason: reason.refine((value) => value.length > 0), idempotencyKey: uuid })
export type ActivateRelationshipInput = z.infer<typeof activateRelationshipSchema>
export type ArchiveRelationshipInput = z.infer<typeof archiveRelationshipSchema>
export type RelationshipCommandResult = { ok: boolean; message: string; refresh: boolean; replayed: boolean }
const messages: Record<string, string> = {
  invalid_request: 'Check the selected documents, relationship and reason.',
  self_relationship: 'Choose two different proceeding documents.',
  not_allowed: 'You do not have permission to change relationships.',
  idempotency_conflict: 'This request no longer matches the earlier attempt. Review your selection before trying again.',
  context_unavailable: 'The matter or selected documents are no longer available.',
  matter_read_only: 'This matter is closed. Relationships cannot be changed.',
  endpoint_unavailable: 'A selected document is no longer active. Review your selection.',
  invalid_endpoint_class: 'Relationships require two active proceeding documents.',
  conflict: 'The selected record changed. The latest records have been loaded; review your selection and confirm again.',
  invalid_relationship_type: 'This relationship type is no longer available.',
  duplicate_active: 'This effective relationship already exists.',
  inverse_conflict: 'The opposite relationship already exists and conflicts with this direction.',
  cycle_detected: 'This relationship would create a circular procedural path. Review the source, target and existing relationships.',
  relationship_unavailable: 'This relationship is no longer effective.',
  write_failed: 'The change could not be saved. Try again.',
}
export function relationshipCommandResult(code: string, replayed = false): RelationshipCommandResult {
  return { ok: code === 'ok', message: code === 'ok' ? (replayed ? 'The earlier change was saved.' : 'Relationship updated.') : messages[code] ?? 'The change could not be confirmed. Try again.', refresh: code === 'ok' || ['conflict', 'duplicate_active', 'context_unavailable', 'endpoint_unavailable', 'relationship_unavailable', 'matter_read_only', 'not_allowed'].includes(code), replayed }
}
