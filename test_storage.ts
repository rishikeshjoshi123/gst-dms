import { createClient } from '@supabase/supabase-js'


const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

async function run() {
  const { data: docs } = await supabase
    .from('documents')
    .select('id, storage_path, matters(id)')
    .order('created_at', { ascending: false })
    .limit(1)

  console.log('Latest document:', docs)

  if (docs && docs.length > 0) {
    const doc = docs[0]
    const { data: objects, error } = await supabase.storage.from('documents').list(doc.storage_path.split('/').slice(0, 2).join('/'))
    console.log('Storage objects under folder:', objects, error)
    
    // Let's check storage.objects directly
    const { data: obj } = await supabase.from('objects').select('name').eq('bucket_id', 'documents').eq('name', doc.storage_path)
    console.log('Object in storage.objects:', obj)
  }
}

run()
