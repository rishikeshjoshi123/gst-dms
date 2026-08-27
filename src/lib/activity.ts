import 'server-only'
import { createServiceClient } from '@/lib/supabase/server'
import type { Database, Json } from '@/lib/supabase/database.types'

type ActivityInput = Pick<Database['public']['Tables']['activity_logs']['Insert'], 'org_id' | 'user_id' | 'action' | 'entity_type' | 'entity_id' | 'description' | 'metadata' | 'is_reversible'>

/** Trusted server/job append boundary. Never expose this to Client Components. */
export async function appendActivity(input: ActivityInput): Promise<void> {
  const { error } = await createServiceClient().from('activity_logs').insert(input)
  if (error) console.error('Trusted activity append failed', { action: input.action })
}
