import pg from 'pg'
const { Client } = pg
const client = new Client({ connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' })

async function run() {
  await client.connect()
  const res = await client.query(`SELECT id, status, suggestion_reason, raw_metadata FROM staged_documents WHERE status = 'ready_to_assign' ORDER BY created_at DESC LIMIT 5`)
  console.log('Docs:', JSON.stringify(res.rows, null, 2))
  await client.end()
}
run().catch(console.error)
