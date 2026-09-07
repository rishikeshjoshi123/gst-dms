import 'server-only'

import { cache } from 'react'

import { createClient } from '@/lib/supabase/server'
import type { Database } from '@/lib/supabase/database.types'

type DirectoryRow = Database['public']['Functions']['get_my_team_members']['Returns'][number]

export type SafeMemberDirectoryEntry = DirectoryRow & {
  id: string
  label: string
}

export const getSafeMemberDirectory = cache(async (): Promise<SafeMemberDirectoryEntry[]> => {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_my_team_members')
  if (error) {
    console.error('Safe member directory error:', error)
    return []
  }

  return (data ?? []).map((member) => ({
    ...member,
    id: member.user_id,
    label: member.display_name?.trim()
      || member.authorised_email
      || `User (${member.user_id.slice(0, 8)})`,
  }))
})

export async function getOperationalMemberOptions() {
  const directory = await getSafeMemberDirectory()
  return directory
    .filter((member) => member.state === 'active' && (member.is_owner || member.role !== 'viewer'))
    .map((member) => ({ id: member.id, email: member.label }))
}
