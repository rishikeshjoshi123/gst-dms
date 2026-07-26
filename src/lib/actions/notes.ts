'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'

export async function getNotes(filters: {
  matterId?: string
  documentId?: string
  isActionItem?: boolean
  templateType?: string
  search?: string
} = {}) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  let query = supabase
    .from('case_notes')
    .select(`
      *,
      matters(id, title),
      documents(id, storage_path, reference_number)
    `)
    .eq('org_id', orgId)
    .is('deleted_at', null)

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
    query = query.eq('template_type', filters.templateType as any)
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

  // Fetch auth users to resolve emails
  try {
    const serviceClient = createServiceClient()
    const { data: { users: authUsers }, error: authError } = await serviceClient.auth.admin.listUsers()
    if (!authError && authUsers) {
      const userMap = new Map(authUsers.map(u => [u.id, u.email]))
      return (data ?? []).map(note => ({
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

  return (data ?? []).map(note => ({
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
}) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const { data: note, error } = await supabase
    .from('case_notes')
    .insert({
      org_id: orgId,
      author_id: user.id,
      matter_id: data.matterId,
      document_id: data.documentId || null,
      content: data.content,
      template_type: data.templateType,
      is_action_item: data.isActionItem,
      action_item_assignee: data.actionItemAssignee || null,
      action_item_due_date: data.actionItemDueDate || null,
      parent_note_id: data.parentNoteId || null,
      quote: data.quote || null,
      page_number: data.pageNumber || null,
      is_pinned: false,
      action_item_resolved: false
    })
    .select()
    .single()

  if (error) {
    console.error('createNote error:', error)
    return { error: error.message }
  }

  revalidatePath('/notes')
  revalidatePath(`/matters/${data.matterId}`)
  if (data.documentId) {
    revalidatePath(`/matters/${data.matterId}/documents/${data.documentId}`)
  }

  const noteWithAuthor = {
    ...note,
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
  action_item_resolved?: boolean
  action_item_assignee?: string | null
  action_item_due_date?: string | null
  template_type?: 'hearing_note' | 'client_instruction' | 'research_note' | 'general'
}) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  const { data: existingNote } = await supabase
    .from('case_notes')
    .select('matter_id, document_id')
    .eq('id', noteId)
    .single()

  const { error } = await supabase
    .from('case_notes')
    .update({
      ...updates,
      updated_at: new Date().toISOString()
    })
    .eq('id', noteId)
    .eq('org_id', orgId)

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
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const db = createServiceClient()

  const { data: existingNote } = await supabase
    .from('case_notes')
    .select('matter_id, document_id')
    .eq('id', noteId)
    .single()

  // Soft delete
  const { error } = await db
    .from('case_notes')
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', noteId)
    .eq('org_id', orgId)

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
