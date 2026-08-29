/**
 * Document Processing Pipeline
 *
 * The durable child worker performs only the fenced provenance extraction
 * write. Later consumer, indexing, notification, and workflow work remain
 * independently owned; they must not inherit an unfenced model payload.
 */

import { task } from '@trigger.dev/sdk/v3'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/lib/supabase/database.types'
import { analyzeDocumentWithOutcome, generateEmbedding } from '@/lib/ai/vertex'
import { logUsage } from '@/lib/actions/usage'
import { buildEmbeddingText, PROMPT_VERSION } from '@/lib/ai/prompts'
import { provenanceMaterializationFromAnalysis } from '@/lib/documents/provenance'
import {
  hasCurrentSearchIndexEmbedding,
  serializeSearchIndexEmbedding,
} from '@/lib/documents/scoped-reprocess'

import {
  VERTEX_DOCUMENT_MODEL,
  VERTEX_EMBEDDING_VERSION,
} from '@/lib/ai/vertex'

const EXTRACTION_MODEL_CONFIG_VERSION = 'vertex-gemini-2-5-flash-v1'
const EXTRACTION_SCHEMA_VERSION = 'document-extraction-v2'
const EXTRACTION_CATALOGUE_VERSION = 'gst-document-types-v1'
const EXTRACTION_NORMALIZER_VERSION = 'candidate-normalizer-v1'

type BeginProvenanceArgs = Database['public']['Functions']['begin_document_processing_ai_extraction']['Args']
type BeginProvenanceRow = Database['public']['Functions']['begin_document_processing_ai_extraction']['Returns'][number]
type FinishProvenanceArgs = Database['public']['Functions']['finish_document_processing_ai_extraction']['Args']
type FinishProvenanceRow = Database['public']['Functions']['finish_document_processing_ai_extraction']['Returns'][number]

async function beginProvenanceExtraction(
  supabase: SupabaseClient<Database>,
  args: BeginProvenanceArgs,
): Promise<BeginProvenanceRow | null> {
  const { data, error } = await supabase.rpc('begin_document_processing_ai_extraction', args)
  if (error) throw new Error('Document provenance RPC unavailable')
  return data?.[0] ?? null
}

async function finishProvenanceExtraction(
  supabase: SupabaseClient<Database>,
  args: FinishProvenanceArgs,
): Promise<FinishProvenanceRow | null> {
  const { data, error } = await supabase.rpc('finish_document_processing_ai_extraction', args)
  if (error) throw new Error('Document provenance RPC unavailable')
  return data?.[0] ?? null
}

export interface ProcessDocumentPayload {
  docId: string
  matterId: string
  orgId: string
  storagePath: string
  uploadedBy: string
  processingRunId?: string
  processingLeaseToken?: string
  documentVersionId?: string
  skipDuplicateCheck?: boolean
}

export const processDocument = task({
  id: 'process-document',
  maxDuration: 300, // 5 minutes max
  retry: {
    maxAttempts: 3,
    minTimeoutInMs: 1000,
    maxTimeoutInMs: 30000,
    factor: 2,
    randomize: true,
  },
  run: async (payload: ProcessDocumentPayload) => {
    const {
      docId,
      matterId,
      orgId,
      storagePath,
      uploadedBy,
      skipDuplicateCheck = false,
    } = payload

    // Lazy-load service client (avoids bundling issues)
    const { createServiceClient } = await import('@/lib/supabase/server')
    const supabase = createServiceClient() as SupabaseClient<Database>

    // ── Step 0: Matter Liveness Guard ────────────────────────────
    console.log(`[Step 0] Checking matter liveness for ${matterId}`)
    const { data: matterCheck } = await supabase
      .from('matters')
      .select('deleted_at, clients!inner(deleted_at)')
      .eq('id', matterId)
      .single()

    const linkedClients = matterCheck?.clients
    const linkedClientDeleted = Array.isArray(linkedClients)
      ? linkedClients.some((client) => client.deleted_at !== null)
      : linkedClients ? linkedClients.deleted_at !== null : false
    if (matterCheck?.deleted_at || linkedClientDeleted) {
      return { status: 'aborted', reason: 'matter_or_client_deleted' }
    }

    if (!payload.processingRunId || !payload.processingLeaseToken || !payload.documentVersionId) {
      // The outbox claim is the only canonical authority for processing. A
      // direct task invocation must not bypass its lease or manufacture a
      // second model call.
      return { status: 'failed', reason: 'processing_lease_required' }
    }

    // ── Step 1: Download from storage ─────────────────────────────
    console.log(`[Step 1] Downloading ${storagePath}`)

    const { data: fileData, error: downloadError } = await supabase.storage
      .from('documents')
      .download(storagePath)

    if (downloadError || !fileData) {
      throw new Error(`[Step 1] Download failed: ${downloadError?.message}`)
    }

    const fileBuffer = Buffer.from(await fileData.arrayBuffer())

    // ── Step 2: Exact duplicate check (SHA-256) ────────────────────
    const { createHash } = await import('crypto')
    const sha256 = createHash('sha256').update(fileBuffer).digest('hex')

    if (!skipDuplicateCheck) {
        console.log('[Step 2] SHA-256 duplicate check')

        const { data: exactDupRaw } = await supabase
          .from('documents')
          .select('id, reference_number')
          .eq('org_id', orgId)
          .eq('file_hash_sha256', sha256)
          .neq('id', docId)
          .is('deleted_at', null)
          .maybeSingle()

        const exactDup = exactDupRaw as { id: string; reference_number: string | null } | null

        if (exactDup) {
          console.warn(`[Step 2] Exact duplicate — matches doc ${exactDup.id}`)
          return { status: 'needs_review', reason: 'exact_duplicate' }
        }
    } else {
      console.log('[Step 2] Skipped exact duplicate check')
    }

    // ── Steps 3–4: provenance run, strict validation, candidates ─────
    console.log('[Step 3] Claiming provenance-bound Vertex analysis')
    const started = await beginProvenanceExtraction(supabase, {
      p_processing_run_id: payload.processingRunId,
      p_processing_lease_token: payload.processingLeaseToken,
      p_provider: 'vertex-ai',
      p_model_identifier: VERTEX_DOCUMENT_MODEL,
      p_model_config_version: EXTRACTION_MODEL_CONFIG_VERSION,
      p_prompt_version: PROMPT_VERSION,
      p_schema_version: EXTRACTION_SCHEMA_VERSION,
      p_catalogue_version: EXTRACTION_CATALOGUE_VERSION,
      p_normalizer_version: EXTRACTION_NORMALIZER_VERSION,
      p_declared_document_id: docId,
      p_declared_document_version_id: payload.documentVersionId,
      p_declared_matter_id: matterId,
      p_declared_org_id: orgId,
      p_declared_bucket_id: 'documents',
      p_declared_object_key: storagePath,
      p_declared_uploaded_by: uploadedBy,
    })

    if (started?.code === 'already_validated') {
      return { status: 'placed', docId }
    } else if (started?.code === 'claimed'
      && typeof started.source_analysis_run_id === 'string'
      && typeof started.source_analysis_lease_token === 'string') {
      const startedAt = Date.now()
      const modelOutcome = await analyzeDocumentWithOutcome(fileBuffer)
      const latencyMs = Date.now() - startedAt
      const usage = modelOutcome.kind === 'validated' ? modelOutcome.result.usage : undefined

      if (modelOutcome.kind !== 'validated') {
        await finishProvenanceExtraction(supabase, {
          p_processing_run_id: payload.processingRunId,
          p_processing_lease_token: payload.processingLeaseToken,
          p_source_analysis_run_id: started.source_analysis_run_id,
          p_source_analysis_lease_token: started.source_analysis_lease_token,
          p_outcome: modelOutcome.kind,
          p_input_tokens: 0,
          p_output_tokens: 0,
          p_latency_ms: latencyMs,
          p_candidates: [],
          p_review_required: true,
          p_legacy_metadata: null,
        })
        return { status: 'needs_review', docId }
      }

      const materialization = provenanceMaterializationFromAnalysis(modelOutcome.result, Number(started.page_count))
      const completed = await finishProvenanceExtraction(supabase, {
        p_processing_run_id: payload.processingRunId,
        p_processing_lease_token: payload.processingLeaseToken,
        p_source_analysis_run_id: started.source_analysis_run_id,
        p_source_analysis_lease_token: started.source_analysis_lease_token,
        p_outcome: materialization.terminalReviewRequired ? 'review_required' : 'validated',
        p_input_tokens: usage?.promptTokens ?? 0,
        p_output_tokens: usage?.candidateTokens ?? 0,
        p_latency_ms: latencyMs,
        p_candidates: materialization.terminalReviewRequired ? [] : materialization.candidates,
        p_review_required: materialization.reviewRequired,
        p_legacy_metadata: materialization.terminalReviewRequired ? null : modelOutcome.result,
      })
      if (completed?.code !== 'validated' && completed?.code !== 'review_required') {
        throw new Error('Document provenance completion was not accepted')
      }
      if (completed.code === 'review_required') return { status: 'needs_review', docId }
      return { status: 'placed', docId }
    } else {
      // Any existing in-flight or terminal run is intentionally not retried
      // here: a new task must never create a second model invocation.
      return { status: 'needs_review', docId }
    }
  },
})

// ================================================================
// Versioned embedding backfill (one matter per run)
// ================================================================

export interface ReindexMatterEmbeddingsPayload {
  matterId: string
  orgId: string
  triggeredBy?: string
}

export const reindexMatterEmbeddings = task({
  id: 'reindex-matter-embeddings',
  maxDuration: 300,
  retry: {
    maxAttempts: 2,
    minTimeoutInMs: 1000,
    maxTimeoutInMs: 15000,
    factor: 2,
  },
  run: async (payload: ReindexMatterEmbeddingsPayload) => {
    const { matterId, orgId, triggeredBy } = payload
    const { createServiceClient } = await import('@/lib/supabase/server')
    const supabase = createServiceClient() as SupabaseClient<Database>

    const { data: matter } = await supabase
      .from('matters')
      .select('id, deleted_at, clients!inner(name, deleted_at)')
      .eq('id', matterId)
      .eq('org_id', orgId)
      .maybeSingle()

    if (!matter || matter.deleted_at || (matter.clients as { deleted_at: string | null }).deleted_at) {
      return { status: 'skipped', reason: 'matter_or_client_unavailable' }
    }

    const clientName = (matter.clients as { name: string }).name
    const { data: documents, error } = await supabase
      .from('documents')
      .select('id, embedding_model, embedding_version, embedding_document_version_id')
      .eq('matter_id', matterId)
      .eq('org_id', orgId)
      .is('deleted_at', null)

    if (error) throw error

    const documentIds = (documents ?? []).map((document) => document.id)
    const { data: projectionRows, error: projectionError } = documentIds.length > 0
      ? await supabase.rpc('read_current_document_search_index_projection', {
          p_org_id: orgId,
          p_document_ids: documentIds,
        })
      : { data: [], error: null }
    if (projectionError) {
      throw new Error('Current Search metadata projection is unavailable')
    }
    const projectionByDocument = new Map((projectionRows ?? []).map((projection) => [projection.document_id, projection]))

    let indexed = 0
    let skipped = 0
    let failed = 0

    for (const document of documents ?? []) {
      const projection = projectionByDocument.get(document.id)
      if (!projection) {
        failed += 1
        continue
      }
      if (hasCurrentSearchIndexEmbedding(document, projection.document_version_id)) {
        skipped += 1
        continue
      }
      const embeddingText = buildEmbeddingText({
        doc_type: projection.doc_type,
        reference_number: projection.reference_number,
        summary: projection.summary,
        financial_years: projection.financial_years,
        issued_by: projection.issued_by,
        client_name: clientName,
      })

      const result = await generateEmbedding(embeddingText, 'RETRIEVAL_DOCUMENT')
      const embedding = result && serializeSearchIndexEmbedding(result)
      if (!embedding || !result) {
        failed += 1
        continue
      }

      const { data: writeRows, error: writeError } = await supabase
        .rpc('write_current_document_search_index_embedding', {
          p_org_id: orgId,
          p_document_id: document.id,
          p_document_version_id: projection.document_version_id,
          p_embedding: embedding,
          p_embedding_model: result.model,
          p_embedding_version: result.version,
          p_input_tokens: result.inputTokens,
          p_projection_fingerprint: projection.projection_fingerprint,
        })

      if (writeError || writeRows?.[0]?.code !== 'indexed') {
        failed += 1
        continue
      }

      await logUsage(supabase, {
        orgId,
        userId: triggeredBy,
        docId: document.id,
        operationType: 'embedding_reindex',
        modelName: result.model,
        inputTokens: result.inputTokens,
        outputTokens: 0,
      })
      indexed += 1
    }

    return {
      status: failed > 0 ? 'partial' : 'complete',
      matterId,
      embeddingVersion: VERTEX_EMBEDDING_VERSION,
      indexed,
      skipped,
      failed,
    }
  },
})

// ================================================================
// Deadline reminder cron (runs daily)
// ================================================================

export const deadlineReminderCron = task({
  id: 'deadline-reminders',
  run: async () => {
    const today = new Date()
    const in7Days = new Date(today)
    in7Days.setDate(in7Days.getDate() + 7)
    const in30Days = new Date(today)
    in30Days.setDate(in30Days.getDate() + 30)

    // TODO (Phase 16): Query approaching deadlines, send reminder emails via Resend

    console.log('[Deadline cron] Checking approaching deadlines...')
    return { checked: true }
  },
})

// ================================================================
// Wiki Generation
// ================================================================

export const generateMatterWiki = task({
  id: 'generate-matter-wiki',
  maxDuration: 120, // 2 minutes max for Gemini
  retry: {
    maxAttempts: 2,
    minTimeoutInMs: 1000,
    maxTimeoutInMs: 10000,
    factor: 2,
  },
  run: async (payload: { matterId: string; orgId: string; triggeredBy: string }) => {
    const { matterId, orgId, triggeredBy } = payload
    const { createServiceClient } = await import('@/lib/supabase/server')
    const supabase = createServiceClient() as SupabaseClient<Database>
    const { generateWikiSummary } = await import('@/lib/ai/vertex')

    // Fetch all processed documents for the matter
    const { data: docs } = await supabase
      .from('documents')
      .select('id, doc_type, doc_date, reference_number, summary, raw_metadata')
      .eq('matter_id', matterId)
      .eq('org_id', orgId)
      .is('deleted_at', null)
      .order('created_at', { ascending: true })

    if (!docs || docs.length === 0) {
      console.log('No documents found for wiki generation.')
      return { success: false, reason: 'No documents' }
    }

    // Compile context
    const contextLines = docs.map(d => {
      return `Document [ID: ${d.id} - ${d.doc_type || 'Unknown'} - ${d.reference_number || 'No Ref'} - Date: ${d.doc_date || 'N/A'}]:
Summary: ${d.summary || 'N/A'}
Details: ${JSON.stringify(d.raw_metadata)}`
    })

    const matterContext = contextLines.join('\n\n')

    // Generate wiki content
    const wikiResult = await generateWikiSummary(matterContext)

    if (!wikiResult) {
      throw new Error('Wiki generation returned null')
    }
    
    if (wikiResult.usage) {
      await logUsage(supabase, {
        orgId,
        userId: triggeredBy,
        docId: null,
        operationType: 'wiki_summary',
        modelName: VERTEX_DOCUMENT_MODEL,
        inputTokens: wikiResult.usage.promptTokens,
        outputTokens: wikiResult.usage.candidateTokens
      })
    }

    const sectionsToUpsert = [
      { key: 'executive_summary', title: 'Executive Summary', content: wikiResult.executive_summary },
      { key: 'key_arguments', title: 'Key Arguments', content: wikiResult.key_arguments },
      { key: 'outstanding_tasks', title: 'Outstanding Tasks', content: wikiResult.outstanding_tasks },
    ]

    for (const sec of sectionsToUpsert) {
      // Check if section exists
      const { data: existing } = await supabase
        .from('wiki_sections')
        .select('id, is_user_edited')
        .eq('matter_id', matterId)
        .eq('section_key', sec.key)
        .maybeSingle()

      if (existing) {
        // Only update content if not user edited, always update last_ai_content
        const updateData: Database['public']['Tables']['wiki_sections']['Update'] = {
          last_ai_content: JSON.stringify({ text: sec.content }),
          updated_at: new Date().toISOString()
        }
        if (!existing.is_user_edited) {
          updateData.content = JSON.stringify({ text: sec.content })
        }
        await supabase.from('wiki_sections').update(updateData).eq('id', existing.id)
      } else {
        await supabase.from('wiki_sections').insert({
          matter_id: matterId,
          section_key: sec.key,
          title: sec.title,
          content: JSON.stringify({ text: sec.content }),
          last_ai_content: JSON.stringify({ text: sec.content }),
          is_user_edited: false
        })
      }
    }

    return { success: true }
  }
})
