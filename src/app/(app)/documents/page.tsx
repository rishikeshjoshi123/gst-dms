import { DocumentHubClientView } from './DocumentHubClientView'

import { getStagedDocuments } from '@/lib/actions/inbox'
import { searchMatterDestinations } from '@/lib/actions/matter'

export const metadata = { title: 'Document Hub — GST Litigation DMS' }

interface DocumentsPageProps {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}

export default async function DocumentsPage({ searchParams }: DocumentsPageProps) {
  const resolvedParams = await searchParams
  const matterId = typeof resolvedParams.matterId === 'string' ? resolvedParams.matterId : undefined
  const intakeId = typeof resolvedParams.intakeId === 'string' ? resolvedParams.intakeId : undefined

  const queueResult = await getStagedDocuments({ includeId: intakeId })
  const requiredMatterIds = queueResult.ok
    ? queueResult.documents.flatMap((document) => document.intake_matter_id ? [document.intake_matter_id] : [])
    : []
  if (matterId) requiredMatterIds.push(matterId)
  const matterResult = await searchMatterDestinations({ includeIds: requiredMatterIds })

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
    />
  )
}
