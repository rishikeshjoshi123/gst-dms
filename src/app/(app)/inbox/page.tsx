import { getStagedDocuments } from '@/lib/actions/inbox'
import { getMatters } from '@/lib/actions/matter'
import { InboxClientView } from './InboxClientView'

export const metadata = { title: 'Document Hub — GST Litigation DMS' }

interface InboxPageProps {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}

export default async function InboxPage({ searchParams }: InboxPageProps) {
  const resolvedParams = await searchParams
  const matterId = typeof resolvedParams.matterId === 'string' ? resolvedParams.matterId : undefined
  const intakeId = typeof resolvedParams.intakeId === 'string' ? resolvedParams.intakeId : undefined

  const documents = await getStagedDocuments()
  const matters = await getMatters()

  return (
    <InboxClientView 
      key={intakeId ?? 'default'}
      initialDocuments={documents} 
      matters={matters}
      preselectedMatterId={matterId}
      preselectedIntakeId={intakeId}
    />
  )
}
