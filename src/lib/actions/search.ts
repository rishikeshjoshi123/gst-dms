'use server'

import { createClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import {
  generateEmbedding,
  VERTEX_EMBEDDING_MODEL,
  VERTEX_EMBEDDING_VERSION,
} from '@/lib/ai/vertex'

export interface SearchResultItem {
  id: string
  title: string
  subtitle?: string
  href: string
  type: 'client' | 'matter' | 'document'
}

type RelatedEntity = { name?: string | null; title?: string | null }
type SearchDocumentRow = {
  id: string
  display_title: string | null
  storage_path: string | null
  reference_number: string | null
  matter_id: string
  matters: unknown
}

function relationValue(
  relation: unknown,
  field: 'name' | 'title',
): string {
  const entity = Array.isArray(relation) ? relation[0] : relation
  if (!entity || typeof entity !== 'object') return ''
  const value = (entity as RelatedEntity)[field]
  return typeof value === 'string' ? value : ''
}

export async function searchAll(query: string, semantic: boolean = false): Promise<SearchResultItem[]> {
  if (!query || query.trim().length < 2) return []
  
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []
  const { data: { user } } = await supabase.auth.getUser()

  const formattedQuery = `%${query.trim()}%`

  // Generate embedding for query (gracefully fallback if it fails)
  let vectorMatches: SearchDocumentRow[] = []
  if (semantic) {
    try {
      const aiResult = await generateEmbedding(query, 'RETRIEVAL_QUERY')
      if (aiResult?.embedding) {
        // Log AI usage for semantic search
        const { logUsage } = await import('@/lib/actions/usage')
        await logUsage(supabase, {
          orgId,
          userId: user?.id,
          operationType: 'semantic_search',
          modelName: VERTEX_EMBEDDING_MODEL,
          inputTokens: aiResult.inputTokens,
          outputTokens: 0
        })

        const { data: vMatchesRes } = await supabase.rpc('match_all_documents_v2', {
          query_embedding: `[${aiResult.embedding.join(',')}]`,
          match_threshold: 0.7,
          match_count: 5,
          p_org_id: orgId,
          p_embedding_model: VERTEX_EMBEDDING_MODEL,
          p_embedding_version: VERTEX_EMBEDDING_VERSION,
        })
        const vMatches = vMatchesRes
        if (vMatches && vMatches.length > 0) {
          // Fetch document details for the vector matches
          const docIds = vMatches.map((match) => match.id)
          const { data: vDocs } = await supabase
            .from('documents')
            .select('id, display_title, storage_path, reference_number, matter_id, matters(title, client_id)')
            .in('id', docIds)
            
          if (vDocs) {
            vectorMatches = vDocs
          }
        }
      }
    } catch (e) {
      console.error('Vector search failed', e)
    }
  }

  const [clientsRes, mattersRes, docsRes] = await Promise.all([
    supabase
      .from('clients')
      .select('id, name, gstin')
      .eq('org_id', orgId)
      .is('deleted_at', null)
      .or(`name.ilike.${formattedQuery},gstin.ilike.${formattedQuery}`)
      .limit(10),
    supabase
      .from('matters')
      .select('id, title, matter_code, client_id, clients(name)')
      .eq('org_id', orgId)
      .is('deleted_at', null)
      .or(`title.ilike.${formattedQuery},matter_code.ilike.${formattedQuery}`)
      .limit(10),
    supabase
      .from('documents')
      .select('id, display_title, storage_path, reference_number, matter_id, matters(title, client_id)')
      .eq('org_id', orgId)
      .is('deleted_at', null)
      .or(`display_title.ilike.${formattedQuery},storage_path.ilike.${formattedQuery},reference_number.ilike.${formattedQuery}`)
      .limit(10)
  ])

  // Combine text matches with vector matches (avoiding duplicates)
  const combinedDocs: SearchDocumentRow[] = (docsRes.data ?? []).map((document) => ({
    ...document,
    matters: document.matters,
  }))
  for (const vDoc of vectorMatches) {
    if (!combinedDocs.some(d => d.id === vDoc.id)) {
      combinedDocs.push(vDoc)
    }
  }

  const results: SearchResultItem[] = []

  // Map Clients
  if (clientsRes.data) {
    for (const client of clientsRes.data) {
      results.push({
        id: client.id,
        title: client.name,
        subtitle: client.gstin ? `GSTIN: ${client.gstin}` : 'Client',
        href: `/clients/${client.id}`,
        type: 'client'
      })
    }
  }

  // Map Matters
  if (mattersRes.data) {
    for (const matter of mattersRes.data) {
      const clientName = relationValue(matter.clients, 'name')
      results.push({
        id: matter.id,
        title: matter.title,
        subtitle: `Matter${clientName ? ` • ${clientName}` : ''}${matter.matter_code ? ` (Code: ${matter.matter_code})` : ''}`,
        href: `/matters/${matter.id}`,
        type: 'matter'
      })
    }
  }

  // Map Documents
  if (combinedDocs.length > 0) {
    for (const doc of combinedDocs) {
      const rawName = doc.storage_path?.split('/').pop()
      const cleanName = rawName?.replace(/^\d+_/, '')
      const matterTitle = relationValue(doc.matters, 'title')
      results.push({
        id: doc.id,
        title: doc.display_title || doc.reference_number || cleanName || 'Document',
        subtitle: `Document${matterTitle ? ` • ${matterTitle}` : ''}${doc.reference_number ? ` (Ref: ${doc.reference_number})` : ''}`,
        href: `/matters/${doc.matter_id}/documents/${doc.id}`,
        type: 'document'
      })
    }
  }

  return results
}
