export const documentLifecycleEventKinds = [
  'document.upload_reserved.v1',
  'document.upload_validation_requested.v1',
  'document.upload_duplicate.v1',
  'document.upload_failed.v1',
  'document.upload_expired.v1',
  'document.intake_validated.v1',
  'document.intake_validation_failed.v1',
  'document.metadata_created.v1',
  'document.processing_requested.v1',
  'document.reprocess_requested.v1',
  'intake.assigned.v1',
  'intake.discarded.v1',
  'trash.operation_created.v1',
  'trash.operation_restored.v1',
  'trash.search_reindex_requested.v1',
  'trash.schedule_reevaluation_requested.v1',
] as const

export type DocumentLifecycleEventKind = typeof documentLifecycleEventKinds[number]
export type SafeOutboxPayload = Record<string, string>

export type DocumentLifecycleEnvelope = {
  eventId: string
  orgId: string
  eventKind: DocumentLifecycleEventKind
  aggregateType: string
  aggregateId: string
  payload: SafeOutboxPayload
  idempotencyKey: string
  leaseToken: string
}

export type LeasedOutboxEvent = DocumentLifecycleEnvelope & { attemptNumber: number }

export const trashRestoreEventKinds = [
  'trash.operation_restored.v1',
  'trash.search_reindex_requested.v1',
  'trash.schedule_reevaluation_requested.v1',
] as const satisfies readonly DocumentLifecycleEventKind[]
export type TrashRestoreEventKind = typeof trashRestoreEventKinds[number]

export const trashOperationEffectEventKinds = [
  'trash.operation_created.v1',
  ...trashRestoreEventKinds,
] as const satisfies readonly DocumentLifecycleEventKind[]
export type TrashOperationEffectEventKind = typeof trashOperationEffectEventKinds[number]

export type OutboxTransport = {
  lease(limit: number, leaseSeconds: number): Promise<LeasedOutboxEvent[]>
  ack(eventId: string, leaseToken: string, triggerRunId: string): Promise<{ code: string }>
  fail(eventId: string, leaseToken: string, safeErrorCode: SafeDispatchErrorCode): Promise<{ code: string }>
}

export type SafeDispatchErrorCode =
  | 'gateway_unavailable'
  | 'gateway_timeout'
  | 'gateway_rejected'
  | 'dispatch_failed'

export type TriggerGateway = {
  trigger(envelope: DocumentLifecycleEnvelope, options: { idempotencyKey: string }): Promise<{ id: string }>
}

// PostgreSQL accepts deterministic UUID fixtures as well as RFC 4122 UUIDs;
// require the complete canonical hexadecimal UUID spelling rather than a
// particular version/variant nibble.
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const safeOpaquePattern = /^[A-Za-z0-9._:-]{1,200}$/
const unsafePayloadKey = /(signed.?url|credential|secret|token|raw|content|ocr|pdf|embedding|storage|object|path|instruction)/i
const safeCodeByKey: Record<string, readonly string[]> = {
  error_code: ['upload_failed', 'invalid_pdf', 'malware_suspect', 'storage_missing', 'validation_failed', 'upload_rejected'],
  result_code: ['ok', 'already_ready', 'not_available', 'invalid_pdf', 'encrypted_pdf', 'malware_suspect', 'storage_missing', 'validation_failed', 'discarded'],
}
const safeScopeValues = ['extract', 'ocr', 'relationships', 'search_index', 'full'] as const

const eventPayloadContracts: Record<DocumentLifecycleEventKind, { aggregateType: 'document' | 'document_upload' | 'trash_operation'; aggregateKey: string; keys: readonly string[] }> = {
  'document.upload_reserved.v1': { aggregateType: 'document_upload', aggregateKey: 'session_id', keys: ['session_id', 'intake_id', 'asset_id'] },
  'document.upload_validation_requested.v1': { aggregateType: 'document_upload', aggregateKey: 'session_id', keys: ['session_id', 'intake_id', 'asset_id'] },
  'document.upload_duplicate.v1': { aggregateType: 'document_upload', aggregateKey: 'session_id', keys: ['session_id', 'intake_id'] },
  'document.upload_failed.v1': { aggregateType: 'document_upload', aggregateKey: 'session_id', keys: ['session_id', 'intake_id', 'error_code'] },
  'document.upload_expired.v1': { aggregateType: 'document_upload', aggregateKey: 'session_id', keys: ['session_id'] },
  'document.intake_validated.v1': { aggregateType: 'document', aggregateKey: 'intake_id', keys: ['intake_id', 'asset_id', 'result_code'] },
  'document.intake_validation_failed.v1': { aggregateType: 'document', aggregateKey: 'intake_id', keys: ['intake_id', 'asset_id', 'result_code'] },
  'document.metadata_created.v1': { aggregateType: 'document', aggregateKey: 'document_id', keys: ['document_id', 'matter_id'] },
  'document.processing_requested.v1': { aggregateType: 'document', aggregateKey: 'document_id', keys: ['document_id', 'version_id', 'intake_id'] },
  'document.reprocess_requested.v1': { aggregateType: 'document', aggregateKey: 'document_id', keys: ['document_id', 'version_id', 'scope'] },
  'intake.assigned.v1': { aggregateType: 'document', aggregateKey: 'intake_id', keys: ['intake_id', 'document_id', 'document_version_id'] },
  'intake.discarded.v1': { aggregateType: 'document', aggregateKey: 'intake_id', keys: ['intake_id', 'result_code'] },
  'trash.operation_created.v1': { aggregateType: 'trash_operation', aggregateKey: 'operation_id', keys: ['operation_id', 'root_resource_id', 'root_resource_type'] },
  'trash.operation_restored.v1': { aggregateType: 'trash_operation', aggregateKey: 'operation_id', keys: ['operation_id', 'root_resource_id', 'root_resource_type'] },
  'trash.search_reindex_requested.v1': { aggregateType: 'trash_operation', aggregateKey: 'operation_id', keys: ['operation_id', 'root_resource_id', 'root_resource_type'] },
  'trash.schedule_reevaluation_requested.v1': { aggregateType: 'trash_operation', aggregateKey: 'operation_id', keys: ['operation_id', 'root_resource_id', 'root_resource_type'] },
}

function isUuid(value: unknown) {
  return typeof value === 'string' && uuidPattern.test(value)
}

export function isSafeOutboxPayload(value: unknown): value is SafeOutboxPayload {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false
  return Object.entries(value).every(([key, item]) => !unsafePayloadKey.test(key)
    && typeof item === 'string'
    && item.length <= 128
    && !/[\u0000-\u001f\u007f]/.test(item))
}

export function isDocumentLifecycleEventKind(value: unknown): value is DocumentLifecycleEventKind {
  return typeof value === 'string' && (documentLifecycleEventKinds as readonly string[]).includes(value)
}

export function isTrashRestoreEventKind(value: unknown): value is TrashRestoreEventKind {
  return typeof value === 'string' && (trashRestoreEventKinds as readonly string[]).includes(value)
}

export function isTrashOperationEffectEventKind(value: unknown): value is TrashOperationEffectEventKind {
  return typeof value === 'string' && (trashOperationEffectEventKinds as readonly string[]).includes(value)
}

export function isSafeLeasedOutboxEvent(value: unknown): value is LeasedOutboxEvent {
  if (!value || typeof value !== 'object') return false
  const event = value as Record<string, unknown>
  if (!isDocumentLifecycleEventKind(event.eventKind) || !isSafeOutboxPayload(event.payload)) return false
  const contract = eventPayloadContracts[event.eventKind]
  const payload = event.payload
  const attemptNumber = event.attemptNumber
  if (!isUuid(event.eventId) || !isUuid(event.orgId) || !isUuid(event.aggregateId) || !isUuid(event.leaseToken)
    || event.aggregateType !== contract.aggregateType
    || typeof event.idempotencyKey !== 'string' || !safeOpaquePattern.test(event.idempotencyKey)
    || typeof attemptNumber !== 'number' || !Number.isInteger(attemptNumber) || attemptNumber <= 0 || attemptNumber > 5) return false
  const keys = Object.keys(payload)
  if (keys.length !== contract.keys.length || keys.some((key) => !contract.keys.includes(key))) return false
  if (payload[contract.aggregateKey] !== event.aggregateId) return false
  return contract.keys.every((key) => {
    const payloadValue = payload[key]
    if (key in safeCodeByKey) return safeCodeByKey[key].includes(payloadValue)
    if (key === 'scope') return safeScopeValues.includes(payloadValue as typeof safeScopeValues[number])
    if (key === 'root_resource_type') return ['client', 'matter', 'document'].includes(payloadValue)
    return isUuid(payloadValue)
  })
}

export function safeDispatchErrorCode(error: unknown): SafeDispatchErrorCode {
  // Gateway exceptions can carry arbitrary provider data. The durable ledger
  // receives a stable operational code only; raw errors never cross this boundary.
  void error
  return 'gateway_unavailable'
}

export function gatewayIdempotencyKey(event: Pick<DocumentLifecycleEnvelope, 'orgId' | 'eventId'>) {
  return `outbox:${event.orgId}:${event.eventId}`
}

export async function dispatchLeasedEvents(
  transport: OutboxTransport,
  gateway: TriggerGateway,
  options: { limit?: number; leaseSeconds?: number; maxBatches?: number } = {},
) {
  const results: Array<{ eventId: string; code: string }> = []
  const limit = options.limit ?? 25
  const leaseSeconds = options.leaseSeconds ?? 120
  const maxBatches = options.maxBatches ?? 1

  for (let batch = 0; batch < maxBatches; batch += 1) {
    const events = await transport.lease(limit, leaseSeconds)
    if (events.length === 0) break

    for (const event of events) {
      if (!isSafeLeasedOutboxEvent(event)) {
        const unsafeEvent = event as unknown as { eventId: string; leaseToken: string }
        const failure = await transport.fail(unsafeEvent.eventId, unsafeEvent.leaseToken, 'dispatch_failed')
        results.push({ eventId: unsafeEvent.eventId, code: failure.code })
        continue
      }
      const { leaseToken } = event
      const envelope: DocumentLifecycleEnvelope = event
      try {
        const run = await gateway.trigger(envelope, { idempotencyKey: gatewayIdempotencyKey(event) })
        const acknowledgement = await transport.ack(event.eventId, leaseToken, run.id)
        results.push({ eventId: event.eventId, code: acknowledgement.code })
      } catch (error) {
        const failure = await transport.fail(event.eventId, leaseToken, safeDispatchErrorCode(error))
        results.push({ eventId: event.eventId, code: failure.code })
      }
    }
  }

  return results
}
