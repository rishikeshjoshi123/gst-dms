import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

async function run() {
  const docId = 'b403f1eb-60c1-4afa-afe7-660d68ae39f5'
  
  const { data: doc } = await supabase.from('documents').select('*').eq('id', docId).single()
  if (!doc) return console.log('Doc not found')

  const { tasks } = await import('@trigger.dev/sdk/v3');
  await tasks.trigger('process-document', {
    docId: doc.id,
    matterId: doc.matter_id,
    orgId: doc.org_id,
    storagePath: doc.storage_path,
    uploadedBy: doc.created_by,
    reprocessMode: 'full'
  })
  
  console.log('Triggered reprocess for', docId)
}

run().catch(console.error)
