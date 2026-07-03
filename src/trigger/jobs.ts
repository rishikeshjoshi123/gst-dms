/**
 * Document Processing Pipeline
 *
 * 13-step Trigger.dev task that processes an uploaded PDF document:
 * 1.  download-from-storage
 * 2.  duplicate-check-exact      (SHA-256 block)
 * 3.  analyze-with-ai            (Vertex AI multimodal)
 * 4.  parse-and-validate         (structured JSON → DB columns)
 * 5.  generate-embedding         (text-embedding-004)
 * 6.  duplicate-check-semantic   (cosine similarity > 0.97 = flag)
 * 7.  content-hash-check         (normalized text hash)
 * 8.  run-chain-placement        (reference matching algorithm)
 * 9.  resolve-pending-links      (scan existing pending links)
 * 10. update-deadlines           (extract + store deadline dates)
 * 11. trigger-wiki-update        (enqueue affected wiki sections)
 * 12. write-logs                 (activity_logs)
 * 13. notify-users               (in-app + email notifications)
 */

import { task } from '@trigger.dev/sdk/v3'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/lib/supabase/database.types'
import { analyzeDocument, generateEmbedding } from '@/lib/ai/vertex'
import { placeDocument, resolvePendingLinks } from '@/lib/actions/chaining'

export interface ProcessDocumentPayload {
  docId: string
  matterId: string
  orgId: string
  storagePath: string
  uploadedBy: string
  /** 'metadata_only' skips chain placement; preserves all links */
  reprocessMode?: 'metadata_only' | 'full'
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
  run: async (payload: ProcessDocumentPayload, { ctx }) => {
    const {
      docId,
      matterId,
      orgId,
      storagePath,
      uploadedBy,
      reprocessMode = 'full',
    } = payload

    // Lazy-load service client (avoids bundling issues)
    const { createServiceClient } = await import('@/lib/supabase/server')
    const supabase = createServiceClient() as SupabaseClient<Database>

    // ── Step 1: Download from storage ─────────────────────────────
    console.log(`[Step 1] Downloading ${storagePath}`)

    const { data: fileData, error: downloadError } = await supabase.storage
      .from('documents')
      .download(storagePath)

    if (downloadError || !fileData) {
      await updateDocStatus(supabase, docId, 'failed', `Download failed: ${downloadError?.message || 'Empty file'}`)
      throw new Error(`[Step 1] Download failed: ${downloadError?.message}`)
    }

    const fileBuffer = Buffer.from(await fileData.arrayBuffer())

    // ── Step 2: Exact duplicate check (SHA-256) ────────────────────
    console.log('[Step 2] SHA-256 duplicate check')

    const { createHash } = await import('crypto')
    const sha256 = createHash('sha256').update(fileBuffer).digest('hex')

    const { data: exactDupRaw } = await supabase
      .from('documents')
      .select('id, reference_number')
      .eq('matter_id', matterId)
      .eq('file_hash_sha256', sha256)
      .neq('id', docId)
      .is('deleted_at', null)
      .maybeSingle()

    const exactDup = exactDupRaw as { id: string; reference_number: string | null } | null

    if (exactDup) {
      await updateDocStatus(supabase, docId, 'failed')
      await createNotification(supabase, {
        orgId,
        userId: uploadedBy,
        type: 'processing_failed',
        title: 'Duplicate document detected',
        body: `This file is identical to an existing document (${exactDup.reference_number ?? exactDup.id}). Upload blocked.`,
        entityType: 'document',
        entityId: exactDup.id,
      })
      throw new Error(`[Step 2] Exact duplicate — matches doc ${exactDup.id}`)
    }

    // Store SHA-256
    await (supabase as SupabaseClient)
      .from('documents')
      .update({ file_hash_sha256: sha256, status: 'processing' })
      .eq('id', docId)

    // ── Step 3: AI analysis ────────────────────────────────────────
    console.log('[Step 3] Vertex AI analysis')

    const aiResult = await analyzeDocument(fileBuffer)

    if (!aiResult) {
      await updateDocStatus(supabase, docId, 'needs_review')
      console.warn('[Step 3] AI analysis returned null — marking needs_review')
      // Graceful degradation: document still accessible, just unanalysed
      return { status: 'needs_review', docId }
    }

    // ── Step 4: Parse and validate ─────────────────────────────────
    console.log('[Step 4] Parsing AI output')

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('documents').update({
      doc_type: aiResult.doc_type,
      reference_number: aiResult.reference_number,
      doc_date: aiResult.doc_date,
      direction: aiResult.direction,
      issued_by: aiResult.issued_by,
      financial_year: aiResult.financial_year,
      summary: aiResult.summary,
      raw_metadata: aiResult as any,
      ai_prompt_version: aiResult.prompt_version,
      status: 'analyzed'
    }).eq('id', docId)

    // ── Step 5: Generate embedding ─────────────────────────────────
    console.log('[Step 5] Generating embedding')

    const embeddingText = [
      aiResult.doc_type || '',
      aiResult.reference_number || '',
      aiResult.summary || ''
    ].join(' ').trim()

    let embeddingStr: string | null = null
    if (embeddingText) {
      const embedding = await generateEmbedding(embeddingText)
      if (embedding) {
        embeddingStr = `[${embedding.join(',')}]`
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await (supabase as any).from('documents').update({ embedding: embeddingStr }).eq('id', docId)
      }
    }

    // ── Step 6: Semantic duplicate check ──────────────────────────
    console.log('[Step 6] Semantic duplicate check (cosine similarity)')

    if (embeddingStr) {
      const { data: similarDocs, error: simError } = await supabase.rpc('match_documents', {
        query_embedding: embeddingStr,
        match_threshold: 0.97,
        match_count: 5,
        p_matter_id: matterId
      })

      if (!simError && similarDocs) {
        const matchedDoc = similarDocs.find((d: any) => d.id !== docId)
        if (matchedDoc) {
          console.warn('[Step 6] Semantic duplicate detected', matchedDoc.id)
          await updateDocStatus(supabase, docId, 'needs_review')
          // Optional: we can add a notification or update review_reason if we had such column
        }
      }
    } else {
      console.warn('[Step 6] No embedding generated, skipping semantic check')
    }

    // ── Step 7: Content hash check ────────────────────────────────
    console.log('[Step 7] Content hash check')

    // TODO (Phase 7): Normalize text, compute hash, compare

    // ── Step 8: Chain placement ────────────────────────────────────
    if (reprocessMode === 'full') {
      console.log('[Step 8] Chain placement')
      await placeDocument(supabase, docId, matterId, orgId, uploadedBy, aiResult)
    } else {
      console.log('[Step 8] Skipped (metadata_only reprocess mode)')
    }

    // ── Step 9: Resolve pending links ─────────────────────────────
    console.log('[Step 9] Resolving pending links')

    if (aiResult.reference_number) {
      const resolvedCount = await resolvePendingLinks(
        supabase, 
        docId, 
        aiResult.reference_number, 
        matterId, 
        aiResult.doc_type || 'OTHER', 
        orgId, 
        uploadedBy
      )
      console.log(`[Step 9] Resolved ${resolvedCount} pending link(s)`)
    }

    // ── Step 10: Update deadlines ─────────────────────────────────
    console.log('[Step 10] Updating deadlines')

    if (aiResult.deadlines && aiResult.deadlines.length > 0) {
      const deadlineRows = aiResult.deadlines.map(dl => ({
        matter_id: matterId,
        document_id: docId,
        type: 'other' as const, // Map safely to enum
        due_date: dl.due_date,
        description: dl.description || dl.type
      }))
      
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error: dlError } = await (supabase as any).from('deadlines').insert(deadlineRows)
      if (dlError) {
        console.error('[Step 10] Error inserting deadlines', dlError)
      }
    }

    // ── Step 11: Trigger wiki update ──────────────────────────────
    console.log('[Step 11] Triggering wiki update')

    // TODO (Phase 13): Enqueue regenerateWiki task for affected sections

    // ── Step 12: Write activity log ───────────────────────────────
    console.log('[Step 12] Writing activity log')

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('activity_logs').insert({
      org_id: orgId,
      user_id: uploadedBy,
      action: 'document_processed',
      entity_type: 'document',
      entity_id: docId,
      description: `Document processed successfully by pipeline`,
      metadata: { pipeline_run_id: ctx.run.id, reprocess_mode: reprocessMode },
      is_reversible: false,
    })

    // ── Step 13: Notify users ─────────────────────────────────────
    console.log('[Step 13] Notifying users')

    await createNotification(supabase, {
      orgId,
      userId: uploadedBy,
      type: 'document_ready',
      title: 'Document analyzed',
      body: 'Your document has been processed and is ready to review.',
      entityType: 'document',
      entityId: docId,
    })

    await updateDocStatus(supabase, docId, 'placed')

    return { status: 'placed', docId }
  },
})

// ================================================================
// Staged document analysis (global upload flow)
// ================================================================

export interface AnalyzeStagedPayload {
  stagedDocId: string
  orgId: string
  uploadedBy: string
  storagePath: string
}

export const analyzeStagedDocument = task({
  id: 'analyze-staged-document',
  maxDuration: 120,
  retry: {
    maxAttempts: 3,
    minTimeoutInMs: 1000,
    maxTimeoutInMs: 15000,
    factor: 2,
  },
  run: async (payload: AnalyzeStagedPayload) => {
    const { stagedDocId, orgId, uploadedBy, storagePath } = payload

    const { createServiceClient } = await import('@/lib/supabase/server')
    const supabase = createServiceClient() as SupabaseClient<Database>

    // Update status to analyzing
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any)
      .from('staged_documents')
      .update({ status: 'analyzing' })
      .eq('id', stagedDocId)

    // TODO (Phase 5+6): Download, analyze with Vertex AI, extract GSTIN,
    // query for matching matters, store suggestions
    
    // 1. Download document
    const { data: fileData, error: downloadError } = await supabase.storage
      .from('staging')
      .download(storagePath)

    if (downloadError || !fileData) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any)
        .from('staged_documents')
        .update({ status: 'failed' })
        .eq('id', stagedDocId)
      throw new Error(`Staged Doc Download failed: ${downloadError?.message}`)
    }

    const fileBuffer = Buffer.from(await fileData.arrayBuffer())

    // 2. Analyze
    const aiResult = await analyzeDocument(fileBuffer)
    
    if (!aiResult) {
      await (supabase as any)
        .from('staged_documents')
        .update({ 
          status: 'failed',
          suggestion_reason: 'AI analysis failed: Gemini model returned invalid response or JSON parsing failed.'
        })
        .eq('id', stagedDocId)
      return { stagedDocId, status: 'failed' }
    }

    let suggestedMatterIds: string[] = []
    let suggestedClientId: string | null = null
    let suggestedMatterId: string | null = null

    if (aiResult && aiResult.gstin) {
      // Find clients with this GSTIN in this org
      const { data: clients } = await supabase
        .from('clients')
        .select('id')
        .eq('org_id', orgId)
        .eq('gstin', aiResult.gstin)
        .is('deleted_at', null)

      if (clients && clients.length > 0) {
        suggestedClientId = clients[0].id
        const clientIds = clients.map(c => c.id)
        // Find matters for these clients
        const { data: matters } = await supabase
          .from('matters')
          .select('id')
          .in('client_id', clientIds)
          .eq('org_id', orgId)
          .is('deleted_at', null)
          .order('created_at', { ascending: false })
          .limit(5)

        if (matters && matters.length > 0) {
          suggestedMatterId = matters[0].id
          suggestedMatterIds = matters.map(m => m.id)
        }
      }
    }

    // 3. Update staged_document
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any)
      .from('staged_documents')
      .update({ 
        status: 'ready_to_assign', 
        suggested_matter_ids: suggestedMatterIds,
        suggested_client_id: suggestedClientId,
        suggested_matter_id: suggestedMatterId,
        raw_metadata: aiResult as any
      })
      .eq('id', stagedDocId)

    // Notify the uploader
    await createNotification(supabase, {
      orgId,
      userId: uploadedBy,
      type: 'staged_doc_ready',
      title: 'Document analyzed — please assign it to a matter',
      body: 'Open the Needs Attention panel to assign this document.',
      entityType: 'staged_document',
      entityId: stagedDocId,
    })

    return { stagedDocId, status: 'ready_to_assign' }
  },
})

// ================================================================
// Deadline reminder cron (runs daily)
// ================================================================
export const deadlineReminderCron = task({
  id: 'deadline-reminders',
  run: async () => {
    const { createServiceClient } = await import('@/lib/supabase/server')
    const supabase = createServiceClient() as SupabaseClient<Database>

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
// Helpers
// ================================================================

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function updateDocStatus(supabase: any, docId: string, status: string, reviewReason?: string) {
  const payload: any = { status }
  if (reviewReason) {
    payload.review_reason = reviewReason
  }
  await supabase.from('documents').update(payload).eq('id', docId)
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function createNotification(supabase: any, opts: {
  orgId: string
  userId: string
  type: string
  title: string
  body: string
  entityType: string
  entityId: string
}) {
  await supabase.from('notifications').insert({
    org_id: opts.orgId,
    user_id: opts.userId,
    type: opts.type,
    title: opts.title,
    body: opts.body,
    entity_type: opts.entityType,
    entity_id: opts.entityId,
  })
}
