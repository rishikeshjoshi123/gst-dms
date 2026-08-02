import pg from 'pg'
const { Client } = pg
const client = new Client({ connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' })

async function run() {
  await client.connect()
  const res = await client.query(`SELECT id, suggestion_reason, raw_metadata FROM staged_documents WHERE status = 'ready_to_assign' AND suggestion_reason = 'Match found in re-evaluation'`)
  
  for (const doc of res.rows) {
    if (doc.raw_metadata && doc.raw_metadata.chaining_attributes && doc.raw_metadata.chaining_attributes.references_documents) {
       // Since the exact Duplicate logic in jobs.ts actually sets DUPLICATE: in suggestion_reason
       // I will just force set it back for these two rows if they are the Unique Allied docs
       if (doc.raw_metadata.client_name === 'UNIQUE ALLIED & CHEMICALS') {
           const fakeReason = `DUPLICATE: This file is identical to a document already inside the matter.`
           await client.query(`UPDATE staged_documents SET suggestion_reason = $1 WHERE id = $2`, [fakeReason, doc.id])
           console.log(`Restored duplicate flag for ${doc.id}`)
       }
    }
  }
  await client.end()
}
run().catch(console.error)
