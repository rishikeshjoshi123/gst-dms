import 'server-only'

import { getCurrentOrgId } from '@/lib/actions/org'
import type { Database } from '@/lib/supabase/database.types'
import { createClient } from '@/lib/supabase/server'

type TrashProjectionRow = Database['public']['Functions']['get_exact_trashed_resource_projection']['Returns'][number]
type ClientRow = Database['public']['Tables']['clients']['Row']
type MatterRow = Database['public']['Tables']['matters']['Row']
type DocumentRow = Database['public']['Tables']['documents']['Row']
export type TrashClientRecord = Pick<ClientRow, 'id' | 'name' | 'gstin' | 'pan'>
export type TrashMatterRecord = Pick<MatterRow, 'id' | 'client_id' | 'title' | 'matter_code' | 'financial_year' | 'status' | 'description'> & {
  clients?: TrashClientRecord | null
}
export type TrashDocumentRecord = Pick<DocumentRow,
  | 'id' | 'matter_id' | 'display_title' | 'effective_filename'
  | 'document_class' | 'document_category' | 'financial_year' | 'reference_number'
  | 'status' | 'review_reason' | 'summary' | 'current_version_id' | 'created_at'
> & { matters?: Pick<TrashMatterRecord, 'id' | 'title'> | null }
type TrashDocumentLink = Pick<Database['public']['Tables']['document_links']['Row'],
  'id' | 'from_doc_id' | 'to_doc_id' | 'link_type' | 'status' | 'match_method' | 'created_at'
>
type TrashWikiSection = Pick<Database['public']['Tables']['wiki_sections']['Row'],
  'id' | 'section_key' | 'title' | 'content' | 'is_user_edited' | 'updated_at'
>
type TrashCaseNote = Pick<Database['public']['Tables']['case_notes']['Row'],
  | 'id' | 'matter_id' | 'document_id' | 'content' | 'template_type'
  | 'is_action_item' | 'action_item_assignee' | 'action_item_due_date' | 'action_item_resolved'
  | 'parent_note_id' | 'quote' | 'page_number' | 'is_pinned' | 'created_at'
> & {
  author?: { id: string; email: string }
  documents?: Pick<TrashDocumentRecord, 'id' | 'reference_number' | 'display_title' | 'effective_filename'> | null
}
type InspectorMetadataRow = Database['public']['Functions']['read_current_document_inspector_projection']['Returns'][number]

export type ExactResourceTrashContext = {
  state: 'trash'
  membershipId: string
  cause: 'direct' | 'inherited'
  parentMembershipId: string | null
  operationId: string
  rootResourceId: string
  rootResourceType: 'client' | 'matter' | 'document'
  rootResourceName: string
  operationState: Database['public']['Enums']['trash_operation_state']
  trashedAt: string
  trashedBy: string | null
  trashedByName: string
  retention: {
    mode: 'manual_only' | 'retention_period'
    days: number | null
    purgeEligibleAt: string | null
    autoPurgeEnabled: boolean
    autoPurgeAt: string | null
    purgeScheduledAt: string | null
    blockerCount: number
  }
  // Display guidance for a later restore UI; never mutation authority.
  canRestore: boolean
}

export type ExactResourceTrashData<Record> = {
  record: Record
  matters: TrashMatterRecord[]
  documents: TrashDocumentRecord[]
  links: TrashDocumentLink[]
  wikiSections: TrashWikiSection[]
  notes: TrashCaseNote[]
  inspectorMetadataRows: InspectorMetadataRow[]
}

export type ExactResourceRead<Record> =
  | { state: 'active'; record: Record }
  | { state: 'trash'; context: ExactResourceTrashContext; data: ExactResourceTrashData<Record> }
  | null

function toTrashContext(row: TrashProjectionRow): ExactResourceTrashContext {
  return {
    state: 'trash',
    membershipId: row.membership_id,
    cause: row.cause,
    parentMembershipId: row.parent_membership_id,
    operationId: row.operation_id,
    rootResourceId: row.root_resource_id,
    rootResourceType: row.root_resource_type,
    rootResourceName: row.root_resource_name,
    operationState: row.operation_state,
    trashedAt: row.trashed_at,
    trashedBy: row.trashed_by,
    trashedByName: row.trashed_by_name,
    retention: {
      mode: row.retention_mode,
      days: row.retention_days,
      purgeEligibleAt: row.purge_eligible_at,
      autoPurgeEnabled: row.auto_purge_enabled,
      autoPurgeAt: row.auto_purge_at,
      purgeScheduledAt: row.purge_scheduled_at,
      blockerCount: row.blocker_count,
    },
    canRestore: row.can_restore,
  }
}

async function getTrashProjection<Record>(
  resourceType: 'client' | 'matter' | 'document',
  resourceId: string,
  expectedMatterId: string | null,
): Promise<{ context: ExactResourceTrashContext; data: ExactResourceTrashData<Record> } | null> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_exact_trashed_resource_projection', {
    p_resource_type: resourceType,
    p_resource_id: resourceId,
    p_expected_matter_id: expectedMatterId,
  })

  const projection = data?.[0]
  if (error || !projection || !projection.resource_record || Array.isArray(projection.resource_record)) return null

  return {
    context: toTrashContext(projection),
    data: {
      record: projection.resource_record as Record,
      matters: Array.isArray(projection.related_matters) ? projection.related_matters as TrashMatterRecord[] : [],
      documents: Array.isArray(projection.related_documents) ? projection.related_documents as TrashDocumentRecord[] : [],
      links: Array.isArray(projection.related_links) ? projection.related_links as TrashDocumentLink[] : [],
      wikiSections: Array.isArray(projection.related_wiki_sections) ? projection.related_wiki_sections as TrashWikiSection[] : [],
      notes: Array.isArray(projection.related_notes) ? projection.related_notes as TrashCaseNote[] : [],
      inspectorMetadataRows: Array.isArray(projection.related_inspector_metadata) ? projection.related_inspector_metadata as InspectorMetadataRow[] : [],
    },
  }
}

export async function getExactClient(id: string): Promise<ExactResourceRead<ClientRow | TrashClientRecord>> {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return null

  const { data } = await supabase
    .from('clients')
    .select('*')
    .eq('id', id)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()

  if (data) return { state: 'active', record: data }
  const trash = await getTrashProjection<TrashClientRecord>('client', id, null)
  return trash ? { state: 'trash', ...trash } : null
}

export async function getExactMatter(id: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return null

  const { data } = await supabase
    .from('matters')
    .select('*, clients(id, name, gstin, pan)')
    .eq('id', id)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()

  if (data) return { state: 'active' as const, record: data }
  const trash = await getTrashProjection<TrashMatterRecord>('matter', id, null)
  return trash ? { state: 'trash' as const, ...trash } : null
}

export async function getExactDocument(matterId: string, documentId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return null

  const { data } = await supabase
    .from('documents')
    .select('*, matters(id, title)')
    .eq('id', documentId)
    .eq('matter_id', matterId)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()

  if (data) return { state: 'active' as const, record: data }
  const trash = await getTrashProjection<TrashDocumentRecord>('document', documentId, matterId)
  return trash ? { state: 'trash' as const, ...trash } : null
}
