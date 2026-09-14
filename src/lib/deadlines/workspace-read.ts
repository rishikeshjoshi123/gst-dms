import 'server-only'

import { createClient } from '@/lib/supabase/server'
import { agendaRowSchema, type ManualDeadlineAgenda } from './manual'

export async function readMatterManualDeadlineAgenda(matterId: string): Promise<ManualDeadlineAgenda> {
  const client = await createClient()
  const { data, error } = await client.rpc('read_matter_manual_legal_deadline_agenda', { p_matter_id: matterId, p_limit: 50 } as never)
  if (error) throw new Error('Unable to load the deadline agenda.')
  const parsed = agendaRowSchema.safeParse((data as unknown[])?.[0])
  if (!parsed.success) throw new Error('The deadline agenda returned an invalid response.')
  return { items: parsed.data.items, timezone: parsed.data.timezone, asOfDate: parsed.data.as_of_date, canMutate: parsed.data.can_mutate }
}
