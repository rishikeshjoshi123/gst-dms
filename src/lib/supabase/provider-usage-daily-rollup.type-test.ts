import type { Database } from './database.types'

type Equal<Left, Right> =
  (<Value>() => Value extends Left ? 1 : 2) extends
  (<Value>() => Value extends Right ? 1 : 2)
    ? true
    : false
type Expect<Condition extends true> = Condition

type DailyRollup = Database['public']['Tables']['provider_usage_daily_rollups']['Row']
type DailyLineItem = Database['public']['Tables']['provider_usage_daily_rollup_line_items']['Row']

export type ProviderUsageDailyRollupPreservesUnknownCost = Expect<Equal<
  Pick<DailyRollup, 'usage_day' | 'event_count' | 'costed_event_count' | 'uncosted_event_count' | 'cost_micro_usd'>,
  {
    usage_day: string
    event_count: number
    costed_event_count: number
    uncosted_event_count: number
    cost_micro_usd: number | null
  }
>>
export type ProviderUsageDailyLineItemPreservesUncostedQuantity = Expect<Equal<
  Pick<DailyLineItem, 'provider_quantity' | 'costed_quantity' | 'uncosted_quantity' | 'cost_micro_usd'>,
  {
    provider_quantity: number
    costed_quantity: number
    uncosted_quantity: number
    cost_micro_usd: number | null
  }
>>

export {}
