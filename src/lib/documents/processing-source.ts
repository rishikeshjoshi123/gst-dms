import { createHash } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/lib/supabase/database.types'

type GrantRow = Database['public']['Functions']['grant_current_document_processing_source']['Returns'][number]
type SourceClient = {
  rpc(name: 'grant_current_document_processing_source', args: { p_processing_run_id: string; p_lease_token: string }): PromiseLike<{ data: GrantRow[] | null; error: unknown }>
  storage: { from(bucket: string): { download(path: string): Promise<{ data: Blob | null; error: unknown }> } }
}

export type ProcessingSource = { versionId: string; bucketId: string; objectKey: string; sha256: string; bytes: Buffer }
export type NestedProcessingLease = {
  processingRunId: string
  processingLeaseToken: string
  sourceAnalysisRunId: string
  sourceAnalysisLeaseToken: string
}

export function processingSourceFailureOutcome(code: Exclude<Awaited<ReturnType<typeof loadCurrentProcessingSource>>['code'], 'ready'>): 'no_work' | 'failed' {
  return code === 'stale_lease' || code === 'source_unavailable' ? 'no_work' : 'failed'
}

export function matchesProcessingSource(grant: GrantRow | null, source: ProcessingSource): boolean {
  return grant?.code === 'ready' && grant.document_version_id === source.versionId && grant.bucket_id === source.bucketId
    && grant.object_key === source.objectKey && grant.expected_sha256 === source.sha256
    && grant.expected_bytes === source.bytes.length
}

export async function grantProcessingSource(client: SourceClient, processingRunId: string, leaseToken: string): Promise<GrantRow | null> {
  const { data, error } = await client.rpc('grant_current_document_processing_source', {
    p_processing_run_id: processingRunId, p_lease_token: leaseToken,
  })
  if (error) throw new Error('Document source authority temporarily unavailable')
  return data?.[0] ?? null
}

export async function runWithCurrentProcessingSource<T>(
  client: SourceClient, processingRunId: string, leaseToken: string, source: ProcessingSource,
  work: () => Promise<T>,
): Promise<{ code: 'ready'; value: T } | { code: 'no_work' }> {
  const grant = await grantProcessingSource(client, processingRunId, leaseToken)
  if (!matchesProcessingSource(grant, source)) return { code: 'no_work' }
  return { code: 'ready', value: await work() }
}

export async function cancelUncalledExtraction(
  supabase: SupabaseClient<Database>, lease: NestedProcessingLease,
): Promise<'no_work' | 'failed'> {
  const { data, error } = await supabase.rpc('cancel_uncalled_document_processing_ai_extraction', {
    p_processing_run_id: lease.processingRunId,
    p_processing_lease_token: lease.processingLeaseToken,
    p_source_analysis_run_id: lease.sourceAnalysisRunId,
    p_source_analysis_lease_token: lease.sourceAnalysisLeaseToken,
  })
  if (error) throw new Error('Document no-call cancellation unavailable')
  return data?.[0]?.code === 'cancelled' || data?.[0]?.code === 'already_cancelled' ? 'no_work' : 'failed'
}

export async function runClaimedModelWithFence<T>(
  supabase: SupabaseClient<Database>, lease: NestedProcessingLease, source: ProcessingSource,
  provider: () => Promise<T>,
): Promise<{ code: 'ready'; value: T } | { code: 'no_work' | 'failed' }> {
  const guarded = await runWithCurrentProcessingSource(
    supabase, lease.processingRunId, lease.processingLeaseToken, source,
    async () => {
      const { data, error } = await supabase.rpc('mark_current_document_processing_ai_provider_call', {
        p_processing_run_id: lease.processingRunId,
        p_processing_lease_token: lease.processingLeaseToken,
        p_source_analysis_run_id: lease.sourceAnalysisRunId,
        p_source_analysis_lease_token: lease.sourceAnalysisLeaseToken,
      })
      if (error) throw new Error('Document provider-call fence unavailable')
      if (data?.[0]?.code !== 'ready') return { code: 'not_started' as const }
      return { code: 'started' as const, value: await provider() }
    },
  )
  if (guarded.code !== 'ready' || guarded.value.code !== 'started') {
    return { code: await cancelUncalledExtraction(supabase, lease) }
  }
  return { code: 'ready', value: guarded.value.value }
}

export async function loadCurrentProcessingSource(
  client: SourceClient, processingRunId: string, leaseToken: string,
): Promise<{ code: 'ready'; source: ProcessingSource } | { code: 'stale_lease' | 'source_unavailable' | 'storage_missing' | 'source_mismatch' }> {
  const grant = await grantProcessingSource(client, processingRunId, leaseToken)
  if (!grant || grant.code !== 'ready' || !grant.document_version_id || !grant.bucket_id || !grant.object_key || !grant.expected_sha256 || !grant.expected_bytes) {
    return { code: grant?.code === 'stale_lease' ? 'stale_lease' : 'source_unavailable' }
  }
  const { data, error } = await client.storage.from(grant.bucket_id).download(grant.object_key)
  if (error) {
    const candidate = error as { status?: unknown; statusCode?: unknown; code?: unknown }
    if (String(candidate?.status) === '404' || String(candidate?.statusCode) === '404' || String(candidate?.code) === '404') {
      return { code: 'storage_missing' }
    }
    throw new Error('Document storage temporarily unavailable')
  }
  if (!data) throw new Error('Document storage response unavailable')
  const bytes = Buffer.from(await data.arrayBuffer())
  if (bytes.length !== grant.expected_bytes || createHash('sha256').update(bytes).digest('hex') !== grant.expected_sha256) {
    return { code: 'source_mismatch' }
  }
  const current = await grantProcessingSource(client, processingRunId, leaseToken)
  if (!current || current.code !== 'ready') return { code: current?.code === 'stale_lease' ? 'stale_lease' : 'source_unavailable' }
  if (!matchesProcessingSource(current, { versionId: grant.document_version_id, bucketId: grant.bucket_id, objectKey: grant.object_key, sha256: grant.expected_sha256, bytes })) {
    return { code: 'source_mismatch' }
  }
  return { code: 'ready', source: { versionId: grant.document_version_id, bucketId: grant.bucket_id, objectKey: grant.object_key, sha256: grant.expected_sha256, bytes } }
}
