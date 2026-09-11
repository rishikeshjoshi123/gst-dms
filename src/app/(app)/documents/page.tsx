import { DocumentHubClientView } from './DocumentHubClientView'

import { getStagedDocuments } from '@/lib/actions/inbox'
import { searchMatterDestinations } from '@/lib/actions/matter'
import { getCurrentOrgId } from '@/lib/actions/org'
import { createClient } from '@/lib/supabase/server'

export const metadata = { title: 'Document Hub — GST Litigation DMS' }

interface DocumentsPageProps {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}

export default async function DocumentsPage({ searchParams }: DocumentsPageProps) {
  const resolvedParams = await searchParams
  const matterId = typeof resolvedParams.matterId === 'string' ? resolvedParams.matterId : undefined
  const intakeId = typeof resolvedParams.intakeId === 'string' ? resolvedParams.intakeId : undefined

  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const orgId = await getCurrentOrgId()
  const { data: contexts } = await supabase.rpc('get_my_organisation_context')
  const currentContext = (contexts ?? []).find((context) =>
    context.org_id === orgId && context.state === 'active')
  const canManageIntake = currentContext?.capabilities.includes('document.intake.assign') ?? false
  const queueResult = canManageIntake
    ? await getStagedDocuments({ includeId: intakeId, ownershipScope: 'mine' })
    : { ok: true as const, documents: [], total: 0, offset: 0, limit: 50 }
  const requiredMatterIds = queueResult.ok
    ? queueResult.documents.flatMap((document) => document.intake_matter_id ? [document.intake_matter_id] : [])
    : []
  if (matterId) requiredMatterIds.push(matterId)
  const matterResult = canManageIntake
    ? await searchMatterDestinations({ includeIds: requiredMatterIds })
    : { ok: true as const, matters: [] }

  return (
    <DocumentHubClientView
      initialDocuments={queueResult.ok ? queueResult.documents : []}
      initialQueueError={queueResult.ok ? null : queueResult.error}
      initialQueueTotal={queueResult.ok ? queueResult.total : 0}
      initialNextOffset={queueResult.ok ? queueResult.offset + queueResult.limit : 0}
      initialMatters={matterResult.ok ? matterResult.matters : []}
      initialMatterLookupError={matterResult.ok ? null : matterResult.error}
      preselectedMatterId={matterId}
      preselectedIntakeId={intakeId}
      currentUserId={user?.id ?? 'anonymous'}
      canManageIntake={canManageIntake}
    />
  )
}
