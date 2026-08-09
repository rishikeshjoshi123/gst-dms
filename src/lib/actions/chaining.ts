import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/lib/supabase/database.types'
import { AIDocumentResult } from '@/lib/ai/vertex'

type LinkType = Database['public']['Enums']['link_type']

// Deterministic rule table for link types
export function inferLinkType(fromDocType: string | null, toDocType: string | null): LinkType {
  const rules: Record<string, Record<string, LinkType>> = {
    'APL-01':  { 'OIO': 'challenges', 'DRC-01': 'challenges' },
    'APL-05':  { 'APL-02': 'challenges', 'OIA': 'challenges' },
    'APL-02':  { 'APL-01': 'arises_from' },
    'OIO':     { 'DRC-01': 'arises_from', 'SCN': 'arises_from' },
    'DRC-07':  { 'OIO': 'summarizes', 'APL-02': 'summarizes' },
    'DRC-03':  { 'APL-01': 'responds_to', 'APL-05': 'responds_to' },
    'REPLY':   { 'DRC-01': 'responds_to', 'SCN': 'responds_to', 'OIO': 'responds_to' },
    'HC_WRIT': { 'GSTAT': 'challenges', 'APL-02': 'challenges' }
  }
  
  if (!fromDocType || !toDocType) return 'responds_to'
  return rules[fromDocType]?.[toDocType] ?? 'responds_to'
}

export async function placeDocument(
  supabase: SupabaseClient<Database>,
  docId: string,
  matterId: string,
  orgId: string,
  uploadedBy: string,
  aiResult: AIDocumentResult
) {
  const docType = aiResult.doc_type
  const refsToFind = aiResult.chaining_attributes.references_documents || []
  
  // Legacy support
  if ((aiResult.chaining_attributes as any).references_document) {
    refsToFind.push((aiResult.chaining_attributes as any).references_document)
  }

  // 1. Progression Inference Fallback
  // If there are no explicitly extracted references, we try to infer based on doc_type.
  if (refsToFind.length === 0) {
    if (docType === 'APL-01' || docType === 'REPLY' || docType === 'APL-02' || docType === 'APL-05' || docType === 'DRC-03' || docType === 'DRC-07') {
      let targetType = ''
      if (docType === 'APL-01') targetType = 'OIO'
      if (docType === 'APL-05') targetType = 'APL-02'
      if (docType === 'APL-02') targetType = 'APL-01'
      if (docType === 'DRC-07') targetType = 'OIO'
      if (docType === 'REPLY') targetType = 'DRC-01'

      if (targetType) {
        const { data: inferred } = await supabase.from('documents')
          .select('id, doc_type')
          .eq('matter_id', matterId)
          .eq('doc_type', targetType)
          .is('deleted_at', null)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle()
        
        if (inferred) {
          await createLink(supabase, docId, inferred.id, docType, inferred.doc_type, 0.55, 'progression_inference', 'pending', null)
          await queueNotification(supabase, orgId, uploadedBy, docId, inferred.id, 'inference')
        }
      }
    }
    return
  }

  // 2. Loop through explicitly extracted references and build links
  for (const refToFind of refsToFind) {
    if (!refToFind) continue
    // 1. Exact Match
    const { data: exactMatch } = await supabase
      .from('documents')
      .select('id, doc_type')
      .eq('matter_id', matterId)
      .eq('reference_number', refToFind)
      .is('deleted_at', null)
      .maybeSingle()

    if (exactMatch) {
      await createLink(supabase, docId, exactMatch.id, docType, exactMatch.doc_type, 0.95, 'exact_reference', 'confirmed', null)
      continue
    }

    // 2. Fuzzy Match
    const { data: fuzzyMatch, error: fuzzyError } = await supabase.rpc('fuzzy_match_reference', {
      p_matter_id: matterId,
      p_reference_number: refToFind
    })
    
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
      if (!fuzzyError && fuzzyMatch && (fuzzyMatch as any).length > 0) {
      const match = (fuzzyMatch as any)[0]
      await createLink(supabase, docId, match.id, docType, match.doc_type, 0.70, 'fuzzy_reference', 'pending', null)
      await queueNotification(supabase, orgId, uploadedBy, docId, match.id, 'fuzzy')
      continue
    }
    // 3. Cross-Matter Search (Warning only)
    const { data: crossMatch } = await supabase
      .from('documents')
      .select('id')
      .eq('org_id', orgId)
      .neq('matter_id', matterId)
      .eq('reference_number', refToFind)
      .is('deleted_at', null)
      .maybeSingle()

    if (crossMatch) {
      // DO NOT LINK! Flag for manual review.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('documents').update({
        status: 'needs_review',
        review_reason: `Referenced document found in a different matter — manual review required before linking.`
      }).eq('id', docId) 
      
      await queueNotification(supabase, orgId, uploadedBy, docId, null, 'cross_matter', refToFind)
      continue
    }

    // 4. Pending Link
    await createLink(supabase, docId, null, docType, null, null, 'pending', 'pending', refToFind)
  }
}

export async function resolvePendingLinks(
  supabase: SupabaseClient<Database>,
  newDocId: string,
  newRefNumber: string,
  matterId: string,
  newDocType: string,
  orgId: string,
  uploadedBy: string
) {
  if (!newRefNumber) return 0
  
  // Find pending links waiting for this reference number in this matter
  const { data: pendingLinks } = await supabase
    .from('document_links')
    .select('id, from_doc_id, documents!document_links_from_doc_id_fkey(matter_id, doc_type)')
    .eq('status', 'pending')
    .is('to_doc_id', null)
    .eq('pending_ref_number', newRefNumber)
    
  if (!pendingLinks || pendingLinks.length === 0) return 0
  
  let resolvedCount = 0
  
  for (const link of pendingLinks) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const fromDocInfo = link.documents as any
    if (fromDocInfo.matter_id !== matterId) continue // only resolve within the same matter
    
    const determinedLinkType = inferLinkType(fromDocInfo.doc_type, newDocType)
    
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('document_links').update({
      to_doc_id: newDocId,
      link_type: determinedLinkType,
      status: 'confirmed',
      pending_ref_number: null,
      confidence: 1.0,
      match_method: 'exact_reference'
    }).eq('id', link.id)
    
    // Log activity
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('activity_logs').insert({
      org_id: orgId,
      user_id: uploadedBy,
      action: 'link_resolved',
      entity_type: 'document_link',
      entity_id: link.id,
      description: `Pending link automatically resolved to new document (${newRefNumber})`,
      metadata: { new_doc_id: newDocId },
      is_reversible: false
    })
    
    resolvedCount++
  }
  
  return resolvedCount
}

async function createLink(
  supabase: SupabaseClient<Database>,
  fromDocId: string,
  toDocId: string | null,
  fromDocType: string | null,
  toDocType: string | null,
  confidence: number | null,
  matchMethod: string,
  status: 'confirmed' | 'pending',
  pendingRefNumber: string | null
) {
  const linkType = inferLinkType(fromDocType, toDocType)

  if (toDocId) {
    // Dedup check for confirmed links
    const { data: existing } = await supabase.from('document_links')
      .select('id')
      .eq('from_doc_id', fromDocId)
      .eq('to_doc_id', toDocId)
      .maybeSingle()

    if (existing) return
  } else if (pendingRefNumber) {
    // Dedup check for pending links — the unique constraint covers (from_doc_id, pending_ref_number)
    const { data: existingPending } = await (supabase as any).from('document_links')
      .select('id')
      .eq('from_doc_id', fromDocId)
      .eq('pending_ref_number', pendingRefNumber)
      .is('to_doc_id', null)
      .maybeSingle()

    if (existingPending) return
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any).from('document_links').insert({
    from_doc_id: fromDocId,
    to_doc_id: toDocId,
    link_type: linkType,
    confidence,
    status,
    match_method: matchMethod,
    pending_ref_number: pendingRefNumber
  })
}


async function queueNotification(
  supabase: SupabaseClient<Database>,
  orgId: string,
  userId: string,
  docId: string,
  targetDocId: string | null,
  reason: 'fuzzy' | 'inference' | 'cross_matter',
  refToFind?: string
) {
  let title = ''
  let body = ''
  
  if (reason === 'cross_matter') {
    title = 'Possible Misfiled Document'
    body = `Document references ${refToFind} which was found in a different matter. Please review.`
  } else {
    title = 'Confirm Document Link'
    body = `A link was automatically inferred. Please confirm it is correct.`
  }
  
  await supabase.from('notifications').insert({
    org_id: orgId,
    user_id: userId,
    type: 'chain_suggestion',
    title,
    body,
    entity_type: 'document',
    entity_id: docId
  } as any)
}


export async function reevaluateMatterLinks(supabase: SupabaseClient<Database>, matterId: string, orgId: string, userId: string) {
  // 1. Get all documents in matter
  const { data: documents } = await supabase
    .from('documents')
    .select('id, doc_type, raw_metadata')
    .eq('matter_id', matterId)
    .is('deleted_at', null)

  if (!documents || documents.length === 0) return { success: true, count: 0 }

  // 2. Delete ALL links EXCEPT manual ones
  const { data: links } = await supabase
    .from('document_links')
    .select('id, match_method')
    .in('from_doc_id', documents.map(d => d.id))
    
  const linksToDelete = links?.filter(l => l.match_method !== 'manual').map(l => l.id) || []
  
  if (linksToDelete.length > 0) {
    await supabase.from('document_links').delete().in('id', linksToDelete)
  }

  let count = 0
  for (const doc of documents) {
    if (doc.raw_metadata) {
      const aiResult = doc.raw_metadata as unknown as AIDocumentResult
      if (!aiResult.chaining_attributes) aiResult.chaining_attributes = {} as any
      try {
        await placeDocument(supabase, doc.id, matterId, orgId, userId, aiResult)
        count++
      } catch (e) {
        console.error('Failed to link document in re-evaluation:', e)
      }
    }
  }

  return { success: true, count }
}
