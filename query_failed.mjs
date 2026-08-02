import pg from 'pg'
const { Client } = pg
const client = new Client({ connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' })

async function run() {
  await client.connect()
  const failedDoc = await client.query(`SELECT * FROM staged_documents WHERE id = '22d3ef1c-0e48-4a4d-aae2-6e045220878e'`)
  console.log('Failed Doc:', JSON.stringify(failedDoc.rows[0], null, 2))
  await client.end()
}
run().catch(console.error)
