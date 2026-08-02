import pg from 'pg'
const { Client } = pg
const client = new Client({ connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' })

async function run() {
  await client.connect()
  const staged = await client.query(`SELECT id, status, created_at, org_id FROM staged_documents WHERE org_id = 'e9908de9-1615-4b08-80ff-3b79ddd6f185' ORDER BY created_at DESC LIMIT 10`)
  console.log('Recent Staged Docs (Rahul):', staged.rows)

  const docs = await client.query(`SELECT id, doc_type, status, review_status, review_reason FROM documents WHERE org_id = 'e9908de9-1615-4b08-80ff-3b79ddd6f185' ORDER BY created_at DESC LIMIT 10`)
  console.log('\nRecent Docs (Rahul):', docs.rows)
  
  await client.end()
}
run().catch(console.error)
