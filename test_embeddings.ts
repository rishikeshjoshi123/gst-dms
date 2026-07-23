import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

async function run() {
  const { data: logs, error: logsErr } = await supabase
    .from('ai_usage_logs')
    .select('*')
    .eq('operation_type', 'embedding_generation')
    
  console.log('Embedding logs:', logs?.length || 0, logsErr || '')

  const { data: docs, error: docsErr } = await supabase
    .from('documents')
    .select('id, reference_number')
    .not('embedding', 'is', null)

  console.log('Docs with embeddings:', docs?.length || 0, docsErr || '')
}

run().catch(console.error)
