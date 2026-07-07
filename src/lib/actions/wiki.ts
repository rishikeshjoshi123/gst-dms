'use server'

import { createClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'
import { tasks } from '@trigger.dev/sdk/v3'

export async function getWikiSections(matterId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  const { data } = await supabase
    .from('wiki_sections')
    .select('*')
    .eq('matter_id', matterId)

  return data ?? []
}

export async function updateWikiSection(sectionId: string, content: string, matterId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const { error } = await supabase
    .from('wiki_sections')
    .update({ 
      content: JSON.stringify({ text: content }), 
      is_user_edited: true,
      updated_by: user.id,
      updated_at: new Date().toISOString()
    })
    .eq('id', sectionId)

  if (error) {
    console.error('Update wiki section error:', error)
    return { error: error.message }
  }

  revalidatePath(`/matters/${matterId}`)
  return { success: true }
}

export async function triggerWikiGeneration(matterId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  try {
    const res = await tasks.trigger('generate-matter-wiki', {
      matterId,
      orgId,
      triggeredBy: user.id
    })
    return { success: true, runId: res.id }
  } catch (err: any) {
    console.error('Failed to trigger generate-matter-wiki:', err)
    return { error: err.message || 'Failed to trigger wiki generation.' }
  }
}
