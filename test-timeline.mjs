import fs from 'fs'

const env = fs.readFileSync('.env.local', 'utf-8')
const key = env.split('\n').find(l => l.startsWith('SUPABASE_SERVICE_ROLE_KEY='))?.split('=')[1]
const url = env.split('\n').find(l => l.startsWith('NEXT_PUBLIC_SUPABASE_URL='))?.split('=')[1]

async function query(table, qs) {
  const res = await fetch(`${url}/rest/v1/${table}?${qs}`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` }
  })
  return res.json()
}

async function main() {
  const clients = await query('clients', 'name=ilike.*aica*&select=*')
  if (!clients || clients.length === 0) {
    console.log("No client found for aica")
    return
  }
  const client = clients[0]
  console.log("Found client:", client.name)

  const matters = await query('matters', `client_id=eq.${client.id}&select=*`)
  if (!matters || matters.length === 0) {
    console.log("No matters found")
    return
  }
  
  for (const matter of matters) {
    console.log(`\nMatter: ${matter.title}`)
    const docs = await query('documents', `matter_id=eq.${matter.id}&select=*`)
    console.log(`Docs (${docs?.length}):`)
    docs?.forEach(d => console.log(`  - ${d.id}: ${d.doc_date} / ${d.storage_path.split('/').pop()}`))
    
    if (docs?.length > 0) {
        const docIds = docs.map(d=>d.id).join(',')
        const links = await query('document_links', `from_doc_id=in.(${docIds})&select=*`)
        console.log(`Links (${links?.length}):`)
        links?.forEach(l => console.log(`  - From ${l.from_doc_id} to ${l.to_doc_id} (${l.link_type})`))
    }

    const staged = await query('staged_documents', `suggested_matter_id=eq.${matter.id}&select=*`)
    console.log(`Staged suggested for this matter (${staged?.length}):`)
    staged?.forEach(s => console.log(`  - ${s.storage_path.split('/').pop()} status: ${s.status}`))
  }
}
main().catch(console.error)
