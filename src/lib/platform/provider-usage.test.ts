import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { recordCompletedDocumentExtractionProviderUsage } from './provider-usage'

function source(relativePath: string) {
  return readFileSync(new URL(relativePath, import.meta.url), 'utf8')
}

test('document extraction usage writer accepts only a server-owned source run and emits fixed diagnostics', () => {
  const adapter = source('./provider-usage.ts')
  const migration = source('../../../supabase/migrations/00106_document_processing_provider_usage_writer.sql')
  const types = source('../supabase/database.types.ts')

  assert.match(adapter, /p_source_analysis_run_id: sourceAnalysisRunId/)
  assert.doesNotMatch(adapter, /orgId|inputTokens|outputTokens|storagePath|providerPayload/)
  assert.match(adapter, /\[Provider usage\] document_extraction_\$\{code\}/)
  assert.match(migration, /source_run\.org_id/)
  assert.match(migration, /source_run\.input_tokens/)
  assert.match(migration, /source_run\.output_tokens/)
  assert.match(migration, /source_run\.provider/)
  assert.match(migration, /source_run\.model_identifier/)
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.record_completed_document_extraction_provider_usage\(uuid\)\s+TO service_role/)
  assert.doesNotMatch(migration, /p_org_id|p_input_tokens|p_output_tokens|p_model_key/)
  assert.match(types, /record_completed_document_extraction_provider_usage: \{[\s\S]*?p_source_analysis_run_id: string[\s\S]*?cost_micro_usd: number \| null/)
  assert.doesNotMatch(adapter, /as unknown as SupabaseClient/)
})

test('a failed accounting response is retried as the same terminal run and accepts a replay result', async () => {
  const calls: Array<{ name: string; args: unknown }> = []
  const responses = [
    { data: null, error: { message: 'unavailable' } },
    { data: [{ code: 'replayed' }], error: null },
  ]
  const supabase = {
    rpc: async (name: string, args: unknown) => {
      calls.push({ name, args })
      return responses.shift()!
    },
  }

  assert.equal(
    await recordCompletedDocumentExtractionProviderUsage(supabase as never, '11111111-1111-1111-1111-111111111111'),
    'writer_unavailable',
  )
  assert.equal(
    await recordCompletedDocumentExtractionProviderUsage(supabase as never, '11111111-1111-1111-1111-111111111111'),
    'replayed',
  )
  assert.deepEqual(calls, [
    {
      name: 'record_completed_document_extraction_provider_usage',
      args: { p_source_analysis_run_id: '11111111-1111-1111-1111-111111111111' },
    },
    {
      name: 'record_completed_document_extraction_provider_usage',
      args: { p_source_analysis_run_id: '11111111-1111-1111-1111-111111111111' },
    },
  ])
})

test('document processing reconciles terminal runs before placement or a replay return', () => {
  const worker = source('../../trigger/jobs.ts')

  assert.match(worker, /already_validated[\s\S]*?reconcileDocumentExtractionProviderUsage\(supabase, started\.source_analysis_run_id\)[\s\S]*?placeValidatedDocumentRelationships/)
  assert.match(worker, /completed\?\.code !== 'validated'[\s\S]*?reconcileDocumentExtractionProviderUsage\(supabase, started\.source_analysis_run_id\)[\s\S]*?completed\.code === 'review_required'/)
  assert.match(worker, /already_terminal[\s\S]*?reconcileDocumentExtractionProviderUsage\(supabase, started\.source_analysis_run_id\)[\s\S]*?return \{ status: 'needs_review', docId \}/)
})
