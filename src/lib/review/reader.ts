import 'server-only'
import { createClient } from '@/lib/supabase/server'
import { reviewDetail, reviewQueueItem, type ReviewFilters } from './model'
import { z } from 'zod'

export async function readReviewQueue(filters?: ReviewFilters, pageSize = 25) {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('read_review_queue', {
    p_status: filters?.status ?? 'needs_review', p_type: filters?.type ?? 'all',
    p_priority: filters?.priority ?? 'all', p_search: filters?.search ?? '', p_page: filters?.page ?? 1, p_page_size: pageSize,
  })
  if (error) throw new Error('Review could not be loaded. Please try again.')
  const result = data?.[0]
  if (!result) return { items: [], totalCount: 0, canResolve: false, authorised: false, asOf: Date.now() }
  return { items: z.array(reviewQueueItem).parse(result.items), totalCount: result.total_count, canResolve: result.can_resolve, authorised: true, asOf: Date.now() }
}
export async function readReviewDetail(itemId: string) {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('read_review_detail', { p_review_item_id: itemId })
  if (error) throw new Error('Review details could not be loaded. Please try again.')
  return data === null ? null : reviewDetail.parse(data)
}
