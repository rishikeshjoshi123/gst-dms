'use server'

import { createClient } from '@/lib/supabase/server'
import { tasks } from '@trigger.dev/sdk/v3'
import { revalidatePath } from 'next/cache'
import { getCurrentOrgId } from './org'

export async function reprocessDocument(docId: string, isStaged: boolean = false) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }
  
  if (isStaged) {
    const { data: staged } = await supabase
      .from('staged_documents')
      .select('org_id, uploaded_by, storage_path')
      .eq('id', docId)
      .eq('org_id', orgId)
      .single()
    if (!staged) return { error: 'Document not found' }

    // Claim only a failed row. The worker then atomically claims the pending
    // state; this prevents two Retry clicks from dispatching two workers.
    const { data: claimed, error } = await supabase
      .from('staged_documents')
      .update({ status: 'pending_assignment', suggestion_reason: null })
      .eq('id', docId)
      .eq('org_id', orgId)
      .eq('status', 'failed')
      .select('id')
      .maybeSingle()
    if (error) return { error: error.message }
    if (!claimed) return { error: 'This document is already being processed or is no longer available for retry.' }
    
    try {
      await tasks.trigger('analyze-staged-document', {
        stagedDocId: docId,
        orgId: staged.org_id,
        uploadedBy: staged.uploaded_by,
        storagePath: staged.storage_path,
      })
    } catch (triggerError) {
      console.error('Failed to queue staged document retry:', triggerError)
      await supabase
        .from('staged_documents')
        .update({ status: 'failed', suggestion_reason: 'Analysis could not be queued. Please retry again.' })
        .eq('id', docId)
        .eq('org_id', orgId)
      return { error: 'Analysis could not be queued. Please retry again.' }
    }
    
    revalidatePath('/inbox')
  } else {
    const { data: doc } = await supabase
      .from('documents')
      .select('matter_id, org_id, storage_path, created_by, raw_metadata, doc_type')
      .eq('id', docId)
      .eq('org_id', orgId)
      .is('deleted_at', null)
      .single()
    if (!doc) return { error: 'Document not found' }

    // Claim a terminal/review state before dispatching, so an in-flight job
    // cannot be retried again and stale UI actions cannot create duplicates.
    const { data: claimed, error } = await supabase
      .from('documents')
      .update({ status: 'processing', raw_metadata: null, doc_type: null })
      .eq('id', docId)
      .eq('org_id', orgId)
      .in('status', ['failed', 'needs_review', 'analyzed', 'placed'])
      .select('id')
      .maybeSingle()
    if (error) return { error: error.message }
    if (!claimed) return { error: 'This document is already being processed or is not ready for retry.' }
    
    try {
      await tasks.trigger('process-document', {
        docId: docId,
        matterId: doc.matter_id,
        orgId: doc.org_id,
        storagePath: doc.storage_path,
        uploadedBy: doc.created_by || '',
        reprocessMode: 'full',
        skipDuplicateCheck: true,
      })
    } catch (triggerError) {
      console.error('Failed to queue document retry:', triggerError)
      await supabase
        .from('documents')
        .update({
          status: 'failed',
          raw_metadata: doc.raw_metadata,
          doc_type: doc.doc_type,
          review_reason: 'Processing could not be queued. Please retry again.',
        })
        .eq('id', docId)
        .eq('org_id', orgId)
      return { error: 'Processing could not be queued. Please retry again.' }
    }
    
    if (doc.matter_id) {
      revalidatePath(`/matters/${doc.matter_id}`)
    }
  }

  return { success: true }
}
