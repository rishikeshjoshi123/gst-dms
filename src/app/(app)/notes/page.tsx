import { getNotes } from '@/lib/actions/notes'
import { getMatters } from '@/lib/actions/matter'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from '@/lib/actions/org'
import { NotesClientView } from './NotesClientView'

export const metadata = { title: 'Notes Hub — GST Litigation DMS' }

export default async function NotesPage() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()

  if (!orgId) {
    return <div className="p-10">No active organisation.</div>
  }

  // Fetch matters
  const matters = await getMatters()

  // Fetch documents for mapping/linking
  const { data: documents } = await supabase
    .from('documents')
    .select('id, storage_path, reference_number, matter_id')
    .eq('org_id', orgId)
    .is('deleted_at', null)

  // Fetch initial notes
  const notes = await getNotes()

  // Fetch users in org for assignee dropdown
  const { data: memberRows } = await supabase
    .from('org_members')
    .select('user_id, role')
    .eq('org_id', orgId)

  const serviceClient = createServiceClient()
  const { data: { users: authUsers } } = await serviceClient.auth.admin.listUsers()
  const userMap = new Map(authUsers.map(u => [u.id, u.email]))

  const usersList = (memberRows ?? []).map((m: any) => ({
    id: m.user_id,
    email: userMap.get(m.user_id) || `User (${m.user_id.slice(0, 8)})`
  }))

  return (
    <NotesClientView
      initialNotes={notes}
      matters={matters}
      documents={documents ?? []}
      users={usersList}
    />
  )
}
