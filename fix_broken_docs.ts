import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

async function run() {
  const { data: docs } = await supabase
    .from('documents')
    .select('*')
    .like('storage_path', 'staged/%')

  if (!docs || docs.length === 0) {
    console.log('No broken docs found')
    return
  }

  for (const doc of docs) {
    const baseName = doc.storage_path.split('/').pop() || 'document.pdf'
    const newPath = `${doc.org_id}/${doc.matter_id}/${Date.now()}_${baseName}`

    const { data: fileData, error: downloadError } = await supabase.storage.from('staging').download(doc.storage_path)
    if (downloadError || !fileData) {
      console.log(`Failed to download ${doc.storage_path} from staging`, downloadError)
      continue
    }

    const { error: uploadError } = await supabase.storage.from('documents').upload(newPath, fileData, { contentType: 'application/pdf' })
    if (uploadError) {
      console.log(`Failed to upload ${newPath} to documents`, uploadError)
      continue
    }

    await supabase.from('documents').update({ storage_path: newPath }).eq('id', doc.id)
    console.log(`Fixed doc ${doc.id}`)
  }
}

run()
