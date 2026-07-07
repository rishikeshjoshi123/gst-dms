const { createClient } = require('@supabase/supabase-js')
require('dotenv').config({ path: '.env.local' })

const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)

async function run() {
  const { data, error } = await supabase.auth.signInWithPassword({
    email: 'trump@company.com',
    password: 'test123456'
  })
  if (error) { console.log("Login error", error); return }

  // Get matter
  const { data: matters } = await supabase.from('matters').select('id, org_id').limit(1)
  if (!matters || matters.length === 0) { console.log("no matters"); return }
  const matterId = matters[0].id
  const orgId = matters[0].org_id

  console.log("Matter ID:", matterId)

  // get documents
  const { data: docs } = await supabase.from('documents').select('*').eq('matter_id', matterId)
  console.log("Documents:", docs.map(d => ({ id: d.id, type: d.doc_type, ref: d.reference_number })))

  // get links
  const { data: links } = await supabase.from('document_links').select('*')
  console.log("Links:", links)
  
}
run()
