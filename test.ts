import { createClient } from '@supabase/supabase-js'
import * as fs from 'fs'

const env = fs.readFileSync('.env.local', 'utf8')
let url = '', key = ''
for (const line of env.split('\n')) {
  if (line.startsWith('NEXT_PUBLIC_SUPABASE_URL=')) url = line.split('=')[1]
  if (line.startsWith('NEXT_PUBLIC_SUPABASE_ANON_KEY=')) key = line.split('=')[1]
}

const supabase = createClient(url, key)

async function run() {
  const { data, error } = await supabase.auth.signInWithPassword({
    email: 'trump@company.com',
    password: 'test123456'
  })
  
  const { data: docs } = await supabase.from('documents').select('id, doc_type, reference_number, raw_metadata')
  console.log("Docs:", JSON.stringify(docs, null, 2))
  
  const { data: links } = await supabase.from('document_links').select('*')
  console.log("Links:", links)
}
run()
