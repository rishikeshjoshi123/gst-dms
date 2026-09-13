import { readReviewQueue, readReviewDetail } from '@/lib/review/reader'
import { parseReviewFilters } from '@/lib/review/model'
import { ReviewClientView } from './ReviewClientView'
import type { Metadata } from 'next'

export const metadata: Metadata = { title: 'Review' }

export default async function ReviewPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const filters = parseReviewFilters(await searchParams)
  const [queue, detail] = await Promise.all([readReviewQueue(filters), filters.item ? readReviewDetail(filters.item) : null])
  return <ReviewClientView queue={queue} detail={detail} filters={filters} asOf={queue.asOf} />
}
