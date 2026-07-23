import { getPendingReviewItems } from '@/lib/actions/notifications'
import { ReviewClientView } from './ReviewClientView'
import type { Metadata } from 'next'

export const metadata: Metadata = { title: 'Pending Review' }

export default async function ReviewPage() {
  const { needsReviewDocs, pendingLinks, openTasks, stagedDocs } = await getPendingReviewItems()

  return (
    <ReviewClientView
      needsReviewDocs={needsReviewDocs}
      pendingLinks={pendingLinks}
      openTasks={openTasks}
      stagedDocs={stagedDocs}
    />
  )
}
