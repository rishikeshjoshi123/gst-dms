import 'server-only'

import { getCurrentOrgId } from '@/lib/actions/org'
import { createClient } from '@/lib/supabase/server'
import type { Database } from '@/lib/supabase/database.types'

export type MatterWorkspaceDocument = Database['public']['Tables']['documents']['Row']
export type MatterWorkspaceLink = Database['public']['Tables']['document_links']['Row']
type NoteQuoteLocator = Database['public']['Functions']['get_note_quote_locators']['Returns'][number]

async function readActiveMatterDocuments(
  matterId: string,
  documentClass: 'proceeding' | 'supporting',
) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  let query = supabase
    .from('documents')
    .select('*')
    .eq('matter_id', matterId)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)

  query = documentClass === 'proceeding'
    ? query.or('document_class.eq.proceeding,document_class.is.null')
    : query.eq('document_class', documentClass)

  const { data, error } = await query
    .order('created_at', { ascending: false })

  if (error) throw new Error(`Unable to load the ${documentClass} document section.`)
  return data ?? []
}

export type MatterWorkspaceCapabilities = {
  canContribute: boolean
}

/** Server-derived UI capabilities; clients never infer permissions from role names. */
export async function readMatterWorkspaceCapabilities(): Promise<MatterWorkspaceCapabilities> {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { canContribute: false }

  const { data, error } = await supabase.rpc('get_my_organisation_context')
  if (error) return { canContribute: false }
  const context = (data ?? []).find((row) => row.org_id === orgId && row.state === 'active')
  return { canContribute: Boolean(context?.capabilities.includes('document.intake.create')) }
}

/**
 * The Timeline inspector reads only notes attached to its already-authorised
 * selected document. It deliberately avoids the Notes workspace's member
 * directory and task-summary projections.
 */
export async function readSelectedDocumentNotes(matterId: string, documentId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data, error } = await supabase
    .from('case_notes')
    .select('*')
    .eq('org_id', orgId)
    .eq('matter_id', matterId)
    .eq('document_id', documentId)
    .is('deleted_at', null)
    .order('is_pinned', { ascending: false })
    .order('created_at', { ascending: false })
  if (error) throw new Error('Unable to load selected-document notes.')

  const notes = data ?? []
  let quoteLocatorByNoteId = new Map<string, NoteQuoteLocator>()
  if (notes.length > 0) {
    const { data: locators, error: locatorError } = await supabase.rpc('get_note_quote_locators', {
      p_note_ids: notes.map((note) => note.id),
    })
    if (locatorError) throw new Error('Unable to load selected-document quotation sources.')
    quoteLocatorByNoteId = new Map((locators ?? []).map((locator) => [locator.note_id, locator]))
  }

  return notes.map((note) => ({
    ...note,
    quotation_locator: quoteLocatorByNoteId.get(note.id) ?? null,
    task_summary: null,
    author: {
      id: note.author_id,
      email: `User (${note.author_id.slice(0, 8)})`,
    },
  }))
}

/** Timeline deliberately excludes supporting and cross-matter documents. */
export function readActiveProceedings(matterId: string) {
  return readActiveMatterDocuments(matterId, 'proceeding')
}

/** Files deliberately reads only active supporting documents. */
export function readActiveSupportingFiles(matterId: string) {
  return readActiveMatterDocuments(matterId, 'supporting')
}

/** Notes needs only safe, same-matter option identity rather than full document rows. */
export async function readActiveNoteDocumentOptions(matterId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data, error } = await supabase
    .from('documents')
    .select('id, matter_id, reference_number, display_title, effective_filename')
    .eq('matter_id', matterId)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .order('created_at', { ascending: false })

  if (error) throw new Error('Unable to load note document options.')
  return data ?? []
}

/**
 * Transitional adapter for legacy document_links. It accepts the already
 * authorised proceeding set and rejects every edge whose two endpoints are not
 * both in that exact set. It never follows an endpoint into another matter.
 */
export async function readTransitionalTimelineLinks(
  proceedingIds: readonly string[],
): Promise<MatterWorkspaceLink[]> {
  const ids = [...new Set(proceedingIds)]
  if (ids.length === 0) return []

  const supabase = await createClient()
  const { data, error } = await supabase
    .from('document_links')
    .select('*')
    .in('from_doc_id', ids)

  if (error) throw new Error('Unable to load the transitional Timeline relationships.')
  const allowedIds = new Set(ids)
  return (data ?? []).filter((link) => (
    allowedIds.has(link.from_doc_id)
    && typeof link.to_doc_id === 'string'
    && allowedIds.has(link.to_doc_id)
  ))
}
