'use server'

import { createClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from './org'
import { revalidatePath } from 'next/cache'
import { after } from 'next/server'
import { tasks } from '@trigger.dev/sdk/v3'

async function matterBelongsToActiveOrg(
  supabase: Awaited<ReturnType<typeof createClient>>,
  matterId: string,
  orgId: string,
) {
  const { data } = await supabase
    .from('matters')
    .select('id')
    .eq('id', matterId)
    .eq('org_id', orgId)
    .eq('record_state', 'active')
    .is('deleted_at', null)
    .maybeSingle()

  return Boolean(data)
}

export async function getWikiSections(matterId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return []

  if (!await matterBelongsToActiveOrg(supabase, matterId, orgId)) return []

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

  if (!await matterBelongsToActiveOrg(supabase, matterId, orgId)) {
    return { error: 'Matter not found.' }
  }

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
    .eq('matter_id', matterId)

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

  if (!await matterBelongsToActiveOrg(supabase, matterId, orgId)) {
    return { error: 'Matter not found.' }
  }

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  after(async () => {
    try {
      await tasks.trigger('generate-matter-wiki', { matterId, orgId, triggeredBy: user.id })
    } catch (err) {
      console.error('Failed to trigger generate-matter-wiki:', err)
    }
  })

  return { success: true }
}
