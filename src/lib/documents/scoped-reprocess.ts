import { VERTEX_EMBEDDING_DIMENSIONS, VERTEX_EMBEDDING_MODEL, VERTEX_EMBEDDING_VERSION, vertexEmbeddingProvider, type EmbeddingProvider, type EmbeddingResult } from '@/lib/ai/vertex'
import { buildEmbeddingText } from '@/lib/ai/prompts'
import { createHash } from 'node:crypto'

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

type PageTextInput = {
  code: string
  pages: Array<{ page_number: number; text: string }> | null
  existing_content_hashes: Array<{
    page_number: number
    char_start: number
    char_end: number
    content_hash: string
  }> | null
}

type PageChunk = {
  ordinal: number
  page_number: number
  char_start: number
  char_end: number
  content: string
  content_hash: string
  embedding?: string
  embedding_model?: string
  embedding_version?: string
  input_tokens?: number
}

function sourceIdentity(chunk: Pick<PageChunk, 'page_number' | 'char_start' | 'char_end' | 'content_hash'>) {
  return `${chunk.page_number}:${chunk.char_start}:${chunk.char_end}:${chunk.content_hash}`
}

export type ScopedSearchIndexWorkerOutcome = 'indexed' | 'not_indexable' | 'failed'
export type SearchEmbedding = Pick<EmbeddingProvider, 'embed'>

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
  if (result.purpose !== 'corpus' || result.model !== VERTEX_EMBEDDING_MODEL
    || result.version !== VERTEX_EMBEDDING_VERSION || !Number.isInteger(result.inputTokens)
    || result.inputTokens < 0 || result.truncated || result.dimensions !== VERTEX_EMBEDDING_DIMENSIONS
    || result.embedding.length !== VERTEX_EMBEDDING_DIMENSIONS
    || (result.billableUsage !== null && (!Number.isInteger(result.billableUsage.quantity) || result.billableUsage.quantity < 0))
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

export function buildSearchPageChunks(input: PageTextInput): PageChunk[] | null {
  if (!Array.isArray(input.pages) || input.pages.length === 0
    || !input.pages.every((page) => Number.isInteger(page.page_number) && page.page_number > 0
      && typeof page.text === 'string' && page.text.length > 0 && page.text.length <= 8000)) return null
  const chunks: PageChunk[] = []
  let ordinal = 0
  for (const page of [...input.pages].sort((a, b) => a.page_number - b.page_number)) {
    // PostgreSQL's substring/char_length anchors Unicode characters rather
    // than JavaScript UTF-16 units. Keep the locators exactly comparable to
    // the private retained source, including documents with astral symbols.
    const characters = Array.from(page.text)
    for (let start = 0; start < characters.length; start += 2800) {
      const rawContent = characters.slice(start, start + 3200).join('')
      const content = rawContent.trim()
      if (!content) continue
      const leadingWhitespace = Array.from(rawContent).findIndex((character) => !/\s/.test(character))
      const contentStart = start + Math.max(leadingWhitespace, 0)
      chunks.push({
        ordinal: ++ordinal,
        page_number: page.page_number,
        char_start: contentStart,
        char_end: contentStart + Array.from(content).length,
        content,
        content_hash: createHash('sha256').update(content, 'utf8').digest('hex'),
      })
    }
  }
  return chunks.length > 0 && chunks.length <= 20000 ? chunks : null
}

async function writePageChunks(
  client: ScopedReprocessRpcClient,
  claim: ScopedSearchIndexClaim,
  chunks: PageChunk[],
) {
  return rpc<{ code: string }>(client, 'write_current_document_search_page_chunks', {
    p_processing_run_id: claim.processing_run_id,
    p_lease_token: claim.lease_token,
    p_chunks: chunks,
  })
}

/**
 * Rebuild the transitional metadata-summary vector for the exact leased
 * document version. No PDF, object path, raw metadata, provider response, or
 * embedding is returned to Trigger; durable completion is a fenced RPC.
 */
export async function runScopedSearchIndexReprocessWorker(
  client: ScopedReprocessRpcClient,
  claim: ScopedSearchIndexClaim,
  embed: SearchEmbedding = vertexEmbeddingProvider,
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

    // Passage text is separately retained source evidence. A missing or
    // incomplete artifact terminalizes the chunk family without falling back
    // to the metadata summary or AI evidence quotes.
    const pageInput = await rpc<PageTextInput>(client, 'get_document_search_page_text_reprocess_input', {
      p_processing_run_id: claim.processing_run_id,
      p_lease_token: claim.lease_token,
    })
    const chunks = pageInput?.code === 'ready' ? buildSearchPageChunks(pageInput) : null
    if (!chunks) {
      const pageWrite = await writePageChunks(client, claim, [])
      if (pageWrite?.code !== 'not_indexable') {
        await finish(client, claim, 'failed')
        return { outcome: 'failed' }
      }
    } else {
      const knownSourceIdentities = new Set(Array.isArray(pageInput?.existing_content_hashes)
        ? pageInput.existing_content_hashes
          .filter((entry) => Number.isInteger(entry?.page_number) && Number.isInteger(entry?.char_start)
            && Number.isInteger(entry?.char_end) && entry.char_start >= 0 && entry.char_end > entry.char_start
            && typeof entry?.content_hash === 'string' && /^[a-f0-9]{64}$/.test(entry.content_hash))
          .map(sourceIdentity)
        : [])
      for (const chunk of chunks) {
        if (knownSourceIdentities.has(sourceIdentity(chunk))) continue
        const embedding = await embed.embed({ input: chunk.content, purpose: 'corpus' })
        const vector = embedding && serializeSearchIndexEmbedding(embedding)
        if (!embedding || !vector) {
          await finish(client, claim, 'failed')
          return { outcome: 'failed' }
        }
        chunk.embedding = vector
        chunk.embedding_model = embedding.model
        chunk.embedding_version = embedding.version
        chunk.input_tokens = embedding.inputTokens
      }
      const pageWrite = await writePageChunks(client, claim, chunks)
      if (pageWrite?.code !== 'indexed') {
        await finish(client, claim, 'failed')
        return { outcome: 'failed' }
      }
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

    const embedding = await embed.embed({ input: text, purpose: 'corpus' })
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
