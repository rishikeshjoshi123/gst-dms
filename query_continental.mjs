import pg from 'pg'
const { Client } = pg
const client = new Client({ connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' })

async function run() {
  await client.connect()
  const clients = await client.query("SELECT * FROM clients WHERE name ILIKE '%continental seeds%'")
  console.log('Clients:', clients.rows)
  
  for (const c of clients.rows) {
    const matters = await client.query(`SELECT * FROM matters WHERE client_id = '${c.id}'`)
    console.log(`\nMatters for client ${c.id}:`, matters.rows)
    
    for (const m of matters.rows) {
      const docs = await client.query(`SELECT id, doc_type, financial_year, status, review_status, created_at FROM documents WHERE matter_id = '${m.id}'`)
      console.log(`\nDocs for matter ${m.id}:`, docs.rows)
    }
  }

  // Also let's check staged_documents to see if any are stuck
  const staged = await client.query(`SELECT id, status, raw_metadata->>'client_name' as client_name, created_at FROM staged_documents WHERE raw_metadata->>'client_name' ILIKE '%continental seeds%'`)
  console.log('\nStaged Documents:', staged.rows)
  
  await client.end()
}
run().catch(console.error)
