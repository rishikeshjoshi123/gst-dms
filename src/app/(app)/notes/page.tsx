import { getNotes } from '@/lib/actions/notes'
import { getMatters } from '@/lib/actions/matter'
import { createClient } from '@/lib/supabase/server'
import { getCurrentOrgId } from '@/lib/actions/org'
import { NotesClientView } from './NotesClientView'
import { getOperationalMemberOptions } from '@/lib/organisation/member-directory'

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

  const usersList = await getOperationalMemberOptions()

  return (
    <NotesClientView
      initialNotes={notes}
      matters={matters}
      documents={documents ?? []}
      users={usersList}
    />
  )
}
