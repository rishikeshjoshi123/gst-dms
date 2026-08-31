import type { Metadata } from 'next'
import { notFound } from 'next/navigation'

import { getTrashPurgeImpact } from '@/lib/trash/purge'
import { PermanentDeleteReview } from './PermanentDeleteReview'

export const metadata: Metadata = { title: 'Permanent deletion — GST Litigation DMS' }

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export default async function PermanentDeletePage({ params }: PageProps<'/trash/[operationId]/permanent-delete'>) {
  const { operationId } = await params
  if (!uuidPattern.test(operationId)) notFound()
  const impact = await getTrashPurgeImpact(operationId)
  if (!impact) notFound()
  return <PermanentDeleteReview impact={impact} />
}
