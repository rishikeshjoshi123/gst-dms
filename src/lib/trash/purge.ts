import 'server-only'

import { createClient } from '@/lib/supabase/server'
import { shapeTrashPurgeImpact, type TrashPurgeImpact } from './purge-model'

export async function getTrashPurgeImpact(operationId: string): Promise<TrashPurgeImpact | null> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_trash_purge_impact', { p_operation_id: operationId })
  if (error) throw new Error('Permanent-delete impact could not be loaded')
  const row = (data as unknown as Array<Record<string, unknown>> | null)?.[0]
  return row ? shapeTrashPurgeImpact(row) : null
}
