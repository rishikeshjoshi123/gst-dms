'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'
import { randomUUID } from 'node:crypto'
import type { Database } from '@/lib/supabase/database.types'
import { batchTaskSummaryNoteIds } from '@/lib/notes/task-summary-batching'

export async function getNotes(filters: {
  matterId?: string
  documentId?: string
  isActionItem?: boolean
  templateType?: string
  search?: string
} = {}) {
  const supabase = await createClient()

  let query = supabase
    .from('case_notes')
    .select(`
      *,
      matters!inner(id, title),
      documents(id, storage_path, reference_number)
    `)
    .is('deleted_at', null)
    .eq('matters.record_state', 'active')
    .is('matters.deleted_at', null)

  if (filters.matterId) {
    query = query.eq('matter_id', filters.matterId)
  }
  if (filters.documentId) {
    query = query.eq('document_id', filters.documentId)
  }
  if (filters.isActionItem !== undefined) {
    query = query.eq('is_action_item', filters.isActionItem)
  }
  if (filters.templateType) {
    query = query.eq('template_type', filters.templateType as Database['public']['Enums']['note_template_type'])
  }
  if (filters.search) {
    query = query.ilike('content', `%${filters.search}%`)
  }

  // Sort: pinned notes first, then latest first
  const { data, error } = await query
    .order('is_pinned', { ascending: false })
    .order('created_at', { ascending: false })

  if (error) {
    console.error('getNotes error:', error)
    return []
  }

  const documentIds = [...new Set((data ?? []).flatMap((note) => note.document_id ? [note.document_id] : []))]
  let readableNotes = data ?? []
  if (documentIds.length > 0) {
    const { data: activeDocuments } = await supabase
      .from('documents')
      .select('id')
      .in('id', documentIds)
      .eq('record_state', 'active')
      .is('deleted_at', null)
    const activeDocumentIds = new Set((activeDocuments ?? []).map((document) => document.id))
    readableNotes = readableNotes.filter((note) => !note.document_id || activeDocumentIds.has(note.document_id))
  }

  // Action-item note fields are immutable legacy origin data. Current Task
  // state is supplied only by the authenticated Task projection.
  const actionItemNoteIds = readableNotes.filter((note) => note.is_action_item).map((note) => note.id)
  const taskSummaryByNoteId = new Map<string, Database['public']['Functions']['get_note_task_summaries']['Returns'][number]>()
  for (const noteIdBatch of batchTaskSummaryNoteIds(actionItemNoteIds)) {
    const { data: taskSummaries, error: taskSummaryError } = await supabase.rpc(
      'get_note_task_summaries',
      { p_note_ids: noteIdBatch },
    )
    if (taskSummaryError) {
      console.error('getNotes Task summaries error:', taskSummaryError)
      continue
    }
    for (const summary of taskSummaries ?? []) {
      taskSummaryByNoteId.set(summary.note_id, summary)
    }
  }
  const notesWithTaskSummaries = readableNotes.map((note) => ({
    ...note,
    task_summary: taskSummaryByNoteId.get(note.id) ?? null,
  }))

  // Fetch auth users to resolve emails
  try {
    const serviceClient = createServiceClient()
    const { data: { users: authUsers }, error: authError } = await serviceClient.auth.admin.listUsers()
    if (!authError && authUsers) {
      const userMap = new Map(authUsers.map(u => [u.id, u.email]))
      return notesWithTaskSummaries.map(note => ({
        ...note,
        author: {
          id: note.author_id,
          email: userMap.get(note.author_id) || `User (${note.author_id.slice(0, 8)})`
        }
      }))
    }
  } catch (err) {
    console.error('Failed to fetch auth users list:', err)
  }

  return notesWithTaskSummaries.map(note => ({
    ...note,
    author: {
      id: note.author_id,
      email: `User (${note.author_id.slice(0, 8)})`
    }
  }))
}

export async function createNote(data: {
  matterId: string
  documentId?: string | null
  content: string
  templateType: 'hearing_note' | 'client_instruction' | 'research_note' | 'general'
  isActionItem: boolean
  actionItemAssignee?: string | null
  actionItemDueDate?: string | null
  parentNoteId?: string | null
  quote?: string | null
  pageNumber?: number | null
  // Callers that can retry a failed submission retain this opaque key.
  idempotencyKey?: string
}) {
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const commandArgs = {
      p_matter_id: data.matterId,
      p_content: data.content,
      p_template_type: data.templateType,
      p_is_action_item: data.isActionItem,
      p_idempotency_key: data.idempotencyKey || randomUUID(),
      ...(data.documentId ? { p_document_id: data.documentId } : {}),
      ...(data.actionItemAssignee ? { p_action_item_assignee: data.actionItemAssignee } : {}),
      ...(data.actionItemDueDate ? { p_action_item_due_date: data.actionItemDueDate } : {}),
      ...(data.parentNoteId ? { p_parent_note_id: data.parentNoteId } : {}),
      ...(data.quote ? { p_quote: data.quote } : {}),
      ...(data.pageNumber !== null && data.pageNumber !== undefined ? { p_page_number: data.pageNumber } : {}),
    }
  const { data: command, error: commandError } = await supabase.rpc(
    'create_note_with_optional_task',
    commandArgs,
  )
  const result = command?.[0]
  if (commandError || !result || result.code !== 'ok' || !result.note_id) {
    console.error('createNote command error:', commandError ?? result?.code)
    const messages: Record<string, string> = {
      context_unavailable: 'Matter or document is unavailable.',
      invalid_assignee: 'Choose an active operational team member.',
      invalid_parent_note: 'The parent note is unavailable.',
      not_allowed: 'You do not have permission to create this note.',
      idempotency_conflict: 'This submission key was already used for another request.',
    }
    return { error: messages[result?.code ?? ''] ?? 'Unable to create this note.' }
  }

  const { data: note, error } = await supabase
    .from('case_notes')
    .select()
    .eq('id', result.note_id)
    .single()
  if (error || !note) {
    console.error('createNote readback error:', error)
    return { error: 'Note was created but could not be loaded. Refresh and try again.' }
  }

  revalidatePath('/notes')
  revalidatePath(`/matters/${data.matterId}`)
  if (data.documentId) {
    revalidatePath(`/matters/${data.matterId}/documents/${data.documentId}`)
  }

  const noteWithAuthor = {
    ...note,
    task_summary: data.isActionItem && result.task_id
      ? (await supabase.rpc('get_note_task_summaries', { p_note_ids: [note.id] })).data?.[0] ?? null
      : null,
    author: {
      id: user.id,
      email: user.email ?? `User (${user.id.slice(0, 8)})`
    }
  }

  return { success: true, note: noteWithAuthor }
}

export async function updateNote(noteId: string, updates: {
  content?: string
  is_pinned?: boolean
  template_type?: 'hearing_note' | 'client_instruction' | 'research_note' | 'general'
}) {
  const supabase = await createClient()

  const { data: existingNote } = await supabase
    .from('case_notes')
    .select('org_id, matter_id, document_id')
    .eq('id', noteId)
    .is('deleted_at', null)
    .maybeSingle()
  if (!existingNote) return { error: 'Note not found.' }
  const { data: activeMatter } = await supabase
    .from('matters')
    .select('id')
    .eq('id', existingNote.matter_id)
    .eq('org_id', existingNote.org_id)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()
  if (!activeMatter) return { error: 'Notes are read-only while this matter is in Trash.' }

  const { error } = await supabase
    .from('case_notes')
    .update({
      ...updates,
      updated_at: new Date().toISOString()
    })
    .eq('id', noteId)
    .eq('org_id', existingNote.org_id)
    .is('deleted_at', null)

  if (error) {
    console.error('updateNote error:', error)
    return { error: error.message }
  }

  revalidatePath('/notes')
  if (existingNote) {
    revalidatePath(`/matters/${existingNote.matter_id}`)
    if (existingNote.document_id) {
      revalidatePath(`/matters/${existingNote.matter_id}/documents/${existingNote.document_id}`)
    }
  }

  return { success: true }
}

export async function deleteNote(noteId: string) {
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const db = createServiceClient()

  const { data: existingNote } = await supabase
    .from('case_notes')
    .select('org_id, matter_id, document_id')
    .eq('id', noteId)
    .is('deleted_at', null)
    .maybeSingle()
  if (!existingNote) return { error: 'Note not found.' }
  const { data: activeMatter } = await supabase
    .from('matters')
    .select('id')
    .eq('id', existingNote.matter_id)
    .eq('org_id', existingNote.org_id)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()
  if (!activeMatter) return { error: 'Notes are read-only while this matter is in Trash.' }

  // Soft delete
  const { error } = await db
    .from('case_notes')
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', noteId)
    .eq('org_id', existingNote.org_id)
    .is('deleted_at', null)

  if (error) {
    console.error('deleteNote error:', error)
    return { error: error.message }
  }

  revalidatePath('/notes')
  if (existingNote) {
    revalidatePath(`/matters/${existingNote.matter_id}`)
    if (existingNote.document_id) {
      revalidatePath(`/matters/${existingNote.matter_id}/documents/${existingNote.document_id}`)
    }
  }

  return { success: true }
}
