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
      await updateDocStatus(supabase, docId, 'failed')
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

    // TODO (Phase 6): Replace with real Vertex AI call
    // const { analyzeDocument } = await import('@/lib/ai/vertex')
    // const aiResult = await analyzeDocument(fileBuffer)
    const aiResult = null // placeholder until Phase 6

    if (!aiResult) {
      await updateDocStatus(supabase, docId, 'needs_review')
      console.warn('[Step 3] AI analysis returned null — marking needs_review')
      // Graceful degradation: document still accessible, just unanalysed
      return { status: 'needs_review', docId }
    }

    // ── Step 4: Parse and validate ─────────────────────────────────
    console.log('[Step 4] Parsing AI output')

    // TODO (Phase 6): Parse aiResult JSON, validate required fields
    await updateDocStatus(supabase, docId, 'analyzed')

    // ── Step 5: Generate embedding ─────────────────────────────────
    console.log('[Step 5] Generating embedding')

    // TODO (Phase 6): Call text-embedding-004
    // const { generateEmbedding } = await import('@/lib/ai/embeddings')
    // const embedding = await generateEmbedding(aiResult.summary + ' ' + ...)
    // await supabase.from('documents').update({ embedding }).eq('id', docId)

    // ── Step 6: Semantic duplicate check ──────────────────────────
    console.log('[Step 6] Semantic duplicate check (cosine similarity)')

    // TODO (Phase 6): Compare embedding against existing docs
    // SELECT id FROM documents WHERE matter_id = $1 AND embedding <=> $2 < 0.03

    // ── Step 7: Content hash check ────────────────────────────────
    console.log('[Step 7] Content hash check')

    // TODO (Phase 7): Normalize text, compute hash, compare

    // ── Step 8: Chain placement ────────────────────────────────────
    if (reprocessMode === 'full') {
      console.log('[Step 8] Chain placement')
      // TODO (Phase 7): Import and run placeDocument()
    } else {
      console.log('[Step 8] Skipped (metadata_only reprocess mode)')
    }

    // ── Step 9: Resolve pending links ─────────────────────────────
    console.log('[Step 9] Resolving pending links')

    // TODO (Phase 7): If reference_number is known, scan document_links
    // for pending_ref_number matches and resolve them

    // ── Step 10: Update deadlines ─────────────────────────────────
    console.log('[Step 10] Updating deadlines')

    // TODO (Phase 8): Extract deadline dates from aiResult.deadlines[]
    // Insert/update rows in deadlines table

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

    // For now: mark ready_to_assign with empty suggestions
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any)
      .from('staged_documents')
      .update({ status: 'ready_to_assign', suggested_matter_ids: [] })
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
async function updateDocStatus(supabase: any, docId: string, status: string) {
  await supabase.from('documents').update({ status }).eq('id', docId)
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
