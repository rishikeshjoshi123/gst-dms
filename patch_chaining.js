const fs = require('fs')
const path = require('path')

const file = path.join(__dirname, 'src/lib/actions/chaining.ts')
let code = fs.readFileSync(file, 'utf8')

const reevalFunc = `
export async function reevaluateMatterLinks(supabase: SupabaseClient<Database>, matterId: string, orgId: string, userId: string) {
  // 1. Get all documents in matter
  const { data: documents } = await supabase
    .from('documents')
    .select('id, doc_type, raw_metadata')
    .eq('matter_id', matterId)
    .is('deleted_at', null)

  if (!documents || documents.length === 0) return { success: true, count: 0 }

  // 2. Get all links
  const { data: links } = await supabase
    .from('document_links')
    .select('from_doc_id, to_doc_id')
    .in('from_doc_id', documents.map(d => d.id))

  const linkedDocIds = new Set<string>()
  if (links) {
    links.forEach(l => {
      linkedDocIds.add(l.from_doc_id)
      if (l.to_doc_id) linkedDocIds.add(l.to_doc_id)
    })
  }

  // 3. Find unlinked documents
  const unlinkedDocs = documents.filter(d => !linkedDocIds.has(d.id))
  
  if (unlinkedDocs.length === 0) return { success: true, count: 0 }

  let count = 0
  for (const doc of unlinkedDocs) {
    if (doc.raw_metadata) {
      const aiResult = doc.raw_metadata as unknown as AIDocumentResult
      if (!aiResult.chaining_attributes) aiResult.chaining_attributes = {}
      try {
        await placeDocument(supabase, doc.id, matterId, orgId, userId, aiResult)
        count++
      } catch (e) {
        console.error('Failed to link document in re-evaluation:', e)
      }
    }
  }

  return { success: true, count }
}
`;

if (!code.includes('reevaluateMatterLinks(')) {
  code += '\n' + reevalFunc;
  fs.writeFileSync(file, code)
}
