'use server'

import { createClient } from '@/lib/supabase/server'
import { tasks } from '@trigger.dev/sdk/v3'
import { revalidatePath } from 'next/cache'

export async function reprocessDocument(docId: string, isStaged: boolean = false) {
  const supabase = await createClient()
  
  if (isStaged) {
    const { data: staged } = await supabase.from('staged_documents').select('org_id, uploaded_by, storage_path').eq('id', docId).single()
    if (!staged) return { error: 'Document not found' }

    const { error } = await supabase.from('staged_documents').update({ status: 'analyzing' }).eq('id', docId)
    if (error) return { error: error.message }
    
    await tasks.trigger('analyze-staged-document', {
      stagedDocId: docId,
      orgId: staged.org_id,
      uploadedBy: staged.uploaded_by,
      storagePath: staged.storage_path
    })
    
    revalidatePath('/inbox')
  } else {
    // For assigned documents, just reset status
    const { data: doc } = await supabase.from('documents').select('matter_id, org_id, storage_path, created_by').eq('id', docId).single()
    if (!doc) return { error: 'Document not found' }

    const { error } = await supabase.from('documents').update({ status: 'processing' }).eq('id', docId)
    if (error) return { error: error.message }
    
    await tasks.trigger('process-document', {
      docId: docId,
      matterId: doc.matter_id,
      orgId: doc.org_id,
      storagePath: doc.storage_path,
      uploadedBy: doc.created_by || '',
      reprocessMode: 'full'
    })
    
    if (doc.matter_id) {
      revalidatePath(`/matters/${doc.matter_id}`)
    }
  }

  return { success: true }
}
