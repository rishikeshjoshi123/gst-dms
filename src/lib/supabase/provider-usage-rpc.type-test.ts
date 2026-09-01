import type { Database } from './database.types'

type Equal<Left, Right> =
  (<Value>() => Value extends Left ? 1 : 2) extends
  (<Value>() => Value extends Right ? 1 : 2)
    ? true
    : false
type Expect<Condition extends true> = Condition

type UsageWriter = Database['public']['Functions']['record_completed_document_extraction_provider_usage']
type UsageWriterRow = UsageWriter['Returns'][number]

export type ProviderUsageWriterAcceptsOnlyServerOwnedRun = Expect<Equal<UsageWriter['Args'], {
  p_source_analysis_run_id: string
}>>
export type ProviderUsageWriterPreservesNullableLedgerOutcome = Expect<Equal<UsageWriterRow, {
  code: string
  cost_micro_usd: number | null
  pricing_version_id: string | null
  provider_usage_event_id: string | null
  quality: Database['public']['Enums']['provider_usage_quality'] | null
}>>

export {}
