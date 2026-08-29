import { VERTEX_EMBEDDING_DIMENSIONS, VERTEX_EMBEDDING_MODEL, VERTEX_EMBEDDING_VERSION, generateEmbedding, type EmbeddingResult } from '@/lib/ai/vertex'
import { buildEmbeddingText } from '@/lib/ai/prompts'

type RpcResult = { data: unknown; error: { message: string } | null }

export type ScopedReprocessRpcClient = {
  rpc(name: string, args: Record<string, unknown>): Promise<RpcResult>
}

export type ScopedSearchIndexClaim = {
  code: 'claimed'
  org_id: string
  processing_run_id: string
  document_id: string
  document_version_id: string
  lease_token: string
}

type SearchIndexInput = {
  code: string
  doc_type: string | null
  reference_number: string | null
  summary: string | null
  financial_years: string[] | null
  issued_by: string | null
  projection_fingerprint: string | null
}

export type ScopedSearchIndexWorkerOutcome = 'indexed' | 'not_indexable' | 'failed'
export type SearchEmbedding = (text: string) => Promise<EmbeddingResult | null>

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function isUuid(value: unknown): value is string {
  return typeof value === 'string' && uuidPattern.test(value)
}

function isProjectionFingerprint(value: unknown): value is string {
  return typeof value === 'string' && /^[a-f0-9]{64}$/.test(value)
}

export function isScopedSearchIndexClaim(value: unknown): value is ScopedSearchIndexClaim {
  if (!value || typeof value !== 'object') return false
  const claim = value as Record<string, unknown>
  const keys = Object.keys(claim)
  if (keys.length !== 6 || keys.some((key) => ![
    'code', 'org_id', 'processing_run_id', 'document_id', 'document_version_id', 'lease_token',
  ].includes(key))) return false
  return claim.code === 'claimed'
    && isUuid(claim.org_id)
    && isUuid(claim.processing_run_id)
    && isUuid(claim.document_id)
    && isUuid(claim.document_version_id)
    && isUuid(claim.lease_token)
}

function firstRpcRow<T>(value: unknown): T | null {
  return Array.isArray(value) && value.length > 0 && value[0] && typeof value[0] === 'object'
    ? value[0] as T
    : null
}

async function rpc<T>(client: ScopedReprocessRpcClient, name: string, args: Record<string, unknown>) {
  const result = await client.rpc(name, args)
  if (result.error) throw new Error('Scoped search-index worker RPC unavailable')
  return firstRpcRow<T>(result.data)
}

export function serializeSearchIndexEmbedding(result: EmbeddingResult) {
  if (result.taskType !== 'RETRIEVAL_DOCUMENT' || result.model !== VERTEX_EMBEDDING_MODEL
    || result.version !== VERTEX_EMBEDDING_VERSION || !Number.isInteger(result.inputTokens)
    || result.inputTokens < 0 || result.truncated
    || result.embedding.length !== VERTEX_EMBEDDING_DIMENSIONS
    || result.embedding.some((value) => !Number.isFinite(value))) return null
  return `[${result.embedding.join(',')}]`
}

export function hasCurrentSearchIndexEmbedding(
  document: {
    embedding_model: string | null
    embedding_version: string | null
    embedding_document_version_id: string | null
  },
  documentVersionId: string,
) {
  return document.embedding_model === VERTEX_EMBEDDING_MODEL
    && document.embedding_version === VERTEX_EMBEDDING_VERSION
    && document.embedding_document_version_id === documentVersionId
}

async function finish(
  client: ScopedReprocessRpcClient,
  claim: ScopedSearchIndexClaim,
  outcome: ScopedSearchIndexWorkerOutcome,
  embedding?: EmbeddingResult,
  projectionFingerprint?: string,
) {
  const args: Record<string, unknown> = {
    p_processing_run_id: claim.processing_run_id,
    p_lease_token: claim.lease_token,
    p_outcome: outcome,
  }
  if (outcome === 'indexed' && embedding) {
    const vector = serializeSearchIndexEmbedding(embedding)
    if (!vector) return null
    args.p_embedding = vector
    args.p_embedding_model = embedding.model
    args.p_embedding_version = embedding.version
    args.p_input_tokens = embedding.inputTokens
  }
  if ((outcome === 'indexed' || outcome === 'not_indexable') && projectionFingerprint) {
    args.p_projection_fingerprint = projectionFingerprint
  }
  return rpc<{ code: string }>(client, 'finish_document_search_index_reprocess_work', args)
}

/**
 * Rebuild the transitional metadata-summary vector for the exact leased
 * document version. No PDF, object path, raw metadata, provider response, or
 * embedding is returned to Trigger; durable completion is a fenced RPC.
 */
export async function runScopedSearchIndexReprocessWorker(
  client: ScopedReprocessRpcClient,
  claim: ScopedSearchIndexClaim,
  embed: SearchEmbedding = (text) => generateEmbedding(text, 'RETRIEVAL_DOCUMENT'),
): Promise<{ outcome: ScopedSearchIndexWorkerOutcome }> {
  try {
    const input = await rpc<SearchIndexInput>(client, 'get_document_search_index_reprocess_input', {
      p_processing_run_id: claim.processing_run_id,
      p_lease_token: claim.lease_token,
    })
    if (!input || input.code !== 'ready' || !isProjectionFingerprint(input.projection_fingerprint)) {
      await finish(client, claim, 'failed')
      return { outcome: 'failed' }
    }

    const text = buildEmbeddingText({
      doc_type: input.doc_type,
      reference_number: input.reference_number,
      summary: input.summary,
      financial_years: Array.isArray(input.financial_years)
        && input.financial_years.every((financialYear) => typeof financialYear === 'string')
        ? input.financial_years
        : [],
      issued_by: input.issued_by,
      client_name: null,
    })
    if (!text) {
      await finish(client, claim, 'not_indexable', undefined, input.projection_fingerprint)
      return { outcome: 'not_indexable' }
    }

    const embedding = await embed(text)
    if (!embedding || !serializeSearchIndexEmbedding(embedding)) {
      await finish(client, claim, 'failed')
      return { outcome: 'failed' }
    }
    const completion = await finish(client, claim, 'indexed', embedding, input.projection_fingerprint)
    return { outcome: completion?.code === 'indexed' ? 'indexed' : 'failed' }
  } catch {
    // Provider and database details can contain tenant material. The durable
    // state records one safe error code; the reconciler owns retries.
    try {
      await finish(client, claim, 'failed')
    } catch {
      // An unavailable completion RPC intentionally leaves the lease for
      // reconciliation instead of manufacturing a success in task output.
    }
    return { outcome: 'failed' }
  }
}
