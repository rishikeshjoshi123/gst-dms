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
import { logUsage } from '@/lib/actions/usage'
import { VERTEX_DOCUMENT_MODEL, VERTEX_EMBEDDING_MODEL } from '@/lib/ai/vertex'

export interface ProcessDocumentPayload {
  docId: string
  matterId: string
  orgId: string
  storagePath: string
  uploadedBy: string
  /** 'metadata_only' skips chain placement; preserves all links */
  reprocessMode?: 'metadata_only' | 'full'
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
  run: async (payload: ProcessDocumentPayload, { ctx }) => {
    const {
      docId,
      matterId,
      orgId,
      storagePath,
      uploadedBy,
      reprocessMode = 'full',
      skipDuplicateCheck = false,
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
    const { createHash } = await import('crypto')
    const sha256 = createHash('sha256').update(fileBuffer).digest('hex')

    if (!skipDuplicateCheck) {
      console.log('[Step 2] SHA-256 duplicate check')

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
        await updateDocStatus(supabase, docId, 'needs_review')
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await (supabase as any).from('documents').update({
          status: 'needs_review',
          review_reason: `Duplicate detected: This file is identical to existing document (${exactDup.reference_number ?? exactDup.id}).`
        }).eq('id', docId)

        await createNotification(supabase, {
          orgId,
          userId: uploadedBy,
          type: 'processing_failed',
          title: 'Duplicate document detected',
          body: `This file is identical to an existing document (${exactDup.reference_number ?? exactDup.id}).`,
          entityType: 'document',
          entityId: exactDup.id,
        })
        
        console.warn(`[Step 2] Exact duplicate — matches doc ${exactDup.id}`)
        return { status: 'needs_review', reason: 'exact_duplicate' }
      }
    } else {
      console.log('[Step 2] Skipped exact duplicate check')
    }

    // Store SHA-256
    await (supabase as SupabaseClient)
      .from('documents')
      .update({ file_hash_sha256: sha256, status: 'processing' })
      .eq('id', docId)

    // ── Step 3: AI analysis ────────────────────────────────────────
    console.log('[Step 3] Vertex AI analysis')

    const aiResult = await analyzeDocument(fileBuffer)

    if (aiResult?.usage) {
      await logUsage(supabase, {
        orgId,
        userId: uploadedBy,
        docId,
        operationType: 'document_analysis',
        modelName: VERTEX_DOCUMENT_MODEL,
        inputTokens: aiResult.usage.promptTokens,
        outputTokens: aiResult.usage.candidateTokens
      })
    }

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
      financial_year: aiResult.financial_years && aiResult.financial_years.length > 0 ? aiResult.financial_years[0] : null,
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
      const res = await generateEmbedding(embeddingText)
      if (res && res.embedding) {
        embeddingStr = `[${res.embedding.join(',')}]`
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        await (supabase as any).from('documents').update({ embedding: embeddingStr }).eq('id', docId)

        await logUsage(supabase, {
          orgId,
          userId: uploadedBy,
          docId,
          operationType: 'embedding_generation',
          modelName: VERTEX_EMBEDDING_MODEL,
          inputTokens: res.charCount, // Treating charCount as token count for pricing purposes
          outputTokens: 0
        })
      }
    }

    // ── Step 6: Semantic duplicate check ──────────────────────────
    if (!skipDuplicateCheck) {
      console.log('[Step 6] Semantic duplicate check (cosine similarity)')

      if (embeddingStr) {
        const { data: similarDocs, error: simError } = await supabase.rpc('match_documents', {
          query_embedding: embeddingStr,
          match_threshold: 0.97,
          match_count: 5,
          p_matter_id: matterId
        })

        if (!simError && similarDocs) {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const matchedDoc = similarDocs.find((d: any) => d.id !== docId)
          if (matchedDoc) {
            console.warn('[Step 6] Semantic duplicate detected', matchedDoc.id)
            await updateDocStatus(supabase, docId, 'needs_review')
          }
        }
      } else {
        console.warn('[Step 6] No embedding generated, skipping semantic check')
      }
    } else {
      console.log('[Step 6] Skipped semantic duplicate check')
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

    // Check for exact duplicate in documents using SHA-256
    const { createHash } = await import('crypto')
    const sha256 = createHash('sha256').update(fileBuffer).digest('hex')

    const { data: exactDup } = await supabase
      .from('documents')
      .select('id, reference_number, matter_id, matters(title)')
      .eq('file_hash_sha256', sha256)
      .is('deleted_at', null)
      .maybeSingle()

    // 2. Analyze
    const aiResult = await analyzeDocument(fileBuffer)
    
    if (aiResult?.usage) {
      await logUsage(supabase, {
        orgId,
        userId: uploadedBy,
        docId: null, // Staged doc, no final doc ID yet
        operationType: 'staged_document_analysis',
        modelName: VERTEX_DOCUMENT_MODEL,
        inputTokens: aiResult.usage.promptTokens,
        outputTokens: aiResult.usage.candidateTokens
      })
    }

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

    if (exactDup) {
      const matterTitle = (exactDup as any).matters?.title || 'Unknown Matter'
      const refNum = exactDup.reference_number || exactDup.id
      await (supabase as any)
        .from('staged_documents')
        .update({
          status: 'ready_to_assign',
          suggested_matter_ids: [exactDup.matter_id],
          suggested_client_id: null,
          suggested_matter_id: exactDup.matter_id,
          suggestion_reason: `DUPLICATE: This file is identical to document "${refNum}" already inside matter "${matterTitle}".`,
          raw_metadata: aiResult as any
        })
        .eq('id', stagedDocId)

      await createNotification(supabase, {
        orgId,
        userId: uploadedBy,
        type: 'processing_failed',
        title: 'Duplicate document uploaded',
        body: `Staged document is identical to document "${refNum}" in matter "${matterTitle}".`,
        entityType: 'staged_document',
        entityId: stagedDocId,
      })

      return { stagedDocId, status: 'ready_to_assign' }
    }

    let matchedClient = null;

    if (aiResult) {
      if (aiResult.gstin) {
        const { data } = await supabase.from('clients').select('id, name').eq('org_id', orgId).eq('gstin', aiResult.gstin).is('deleted_at', null).maybeSingle();
        if (data) matchedClient = data;
      }
      if (!matchedClient && aiResult.client_identifiers && aiResult.client_identifiers.length > 0) {
        const { data: allClients } = await supabase.from('clients').select('id, name, pan, gstin').eq('org_id', orgId).is('deleted_at', null);
        if (allClients) {
          outer: for (const client of allClients) {
            for (const idStr of aiResult.client_identifiers) {
              if (client.pan && idStr.includes(client.pan)) {
                matchedClient = client;
                break outer;
              }
              if (client.gstin && idStr.includes(client.gstin)) {
                matchedClient = client;
                break outer;
              }
            }
          }
        }
      }
      if (!matchedClient && aiResult.client_name) {
        const { data } = await supabase.from('clients').select('id, name').eq('org_id', orgId).ilike('name', `%${aiResult.client_name}%`).is('deleted_at', null).maybeSingle();
        if (data) matchedClient = data;
      }
    }

    if (matchedClient) {
      // @ts-ignore
      const fys = (aiResult && (aiResult as any).financial_years && (aiResult as any).financial_years.length > 0) ? (aiResult as any).financial_years : ['Unknown FY'];
      
      const createdMatterIds: string[] = [];
      const baseName = storagePath.split('/').pop() || 'document.pdf'
      const { data: fileData } = await supabase.storage.from('staging').download(storagePath)

      for (const fy of fys) {
        let { data: matter } = await supabase.from('matters').select('id').eq('org_id', orgId).eq('client_id', matchedClient.id).eq('financial_year', fy).is('deleted_at', null).maybeSingle();
        
        if (!matter) {
          const { data: newMatter } = await supabase.from('matters').insert({
            org_id: orgId,
            client_id: matchedClient.id,
            financial_year: fy,
            title: fy === 'Unknown FY' ? 'General Matter' : `FY ${fy}`,
            status: 'active'
          }).select('id').single();
          matter = newMatter;
        }

        if (matter) {
          createdMatterIds.push(matter.id);
          
          let newStoragePath = storagePath;
          if (fileData) {
            const path = `${orgId}/${matter.id}/${Date.now()}_${baseName}`
            const { error: uploadErr } = await supabase.storage.from('documents').upload(path, fileData, { contentType: 'application/pdf' })
            if (!uploadErr) {
              newStoragePath = path;
            }
          }

          const { data: newDoc } = await supabase.from('documents').insert({
            org_id: orgId,
            matter_id: matter.id,
            storage_path: newStoragePath,
            created_by: uploadedBy,
            status: 'processing',
            review_status: 'unreviewed',
            doc_type: aiResult.doc_type || 'OTHER',
            direction: aiResult.direction || 'incoming',
            document_class: aiResult.document_class || 'proceeding',
            financial_year: fy,
            raw_metadata: aiResult as any
          }).select('id').single();

          if (newDoc) {
             const { tasks } = await import('@trigger.dev/sdk/v3');
             await tasks.trigger('process-document', {
               docId: newDoc.id,
               matterId: matter.id,
               orgId: orgId,
               storagePath: newStoragePath,
               uploadedBy: uploadedBy,
               reprocessMode: 'full'
             })
          }
        }
      }

      if (fileData) {
        await supabase.storage.from('staging').remove([storagePath]);
      }
      await supabase.from('staged_documents').delete().eq('id', stagedDocId);
      
      await createNotification(supabase, {
        orgId,
        userId: uploadedBy,
        type: 'document_ready',
        title: 'Document Auto-Assigned',
        body: `Document automatically assigned to ${matchedClient.name} for ${fys.join(', ')}.`,
        entityType: 'client',
        entityId: matchedClient.id,
      })

      return { stagedDocId, status: 'auto_assigned' };
    }

    // 3. If no client found, just update staged_document with ready_to_assign so user can do it manually
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any)
      .from('staged_documents')
      .update({ 
        status: 'ready_to_assign', 
        suggested_matter_ids: [],
        suggested_client_id: null,
        suggested_matter_id: null,
        raw_metadata: aiResult as any
      })
      .eq('id', stagedDocId)

    // Notify the uploader
    await createNotification(supabase, {
      orgId,
      userId: uploadedBy,
      type: 'staged_doc_ready',
      title: 'Action Required: Assign Document',
      body: 'We could not automatically match the client. Please assign manually.',
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
// Retry failed documents cron (runs hourly)
// ================================================================
export const retryFailedDocumentsCron = task({
  id: 'retry-failed-documents',
  run: async () => {
    const { createServiceClient } = await import('@/lib/supabase/server')
    const supabase = createServiceClient() as SupabaseClient<Database>
    const { tasks } = await import('@trigger.dev/sdk/v3')

    console.log('[Retry cron] Fetching failed documents...')
    const { data: failedDocs } = await supabase
      .from('documents')
      .select('id, matter_id, org_id, storage_path, created_by')
      .eq('status', 'failed')
      .is('deleted_at', null)
      .limit(50)

    if (failedDocs && failedDocs.length > 0) {
      console.log(`[Retry cron] Found ${failedDocs.length} failed documents. Triggering reprocessing...`)
      
      for (const doc of failedDocs) {
        await tasks.trigger('process-document', {
          docId: doc.id,
          matterId: doc.matter_id,
          orgId: doc.org_id,
          storagePath: doc.storage_path,
          uploadedBy: doc.created_by,
          reprocessMode: 'full'
        })
      }
    }

    return { retried: failedDocs?.length || 0 }
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
      return `Document [${d.doc_type || 'Unknown'} - ${d.reference_number || 'No Ref'} - Date: ${d.doc_date || 'N/A'}]:
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
        const updateData: any = {
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
