const fs = require('fs')
const path = require('path')

const file = path.join(__dirname, 'src/lib/actions/document.ts')
let code = fs.readFileSync(file, 'utf8')

const updateFunc = `
export async function updateDocumentMetadata(docId: string, metadataKey: string, newValue: any) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  // Get current metadata
  const { data: doc } = await supabase
    .from('documents')
    .select('raw_metadata, matter_id')
    .eq('id', docId)
    .eq('org_id', orgId)
    .single()

  if (!doc) return { error: 'Document not found' }

  let currentMetadata = doc.raw_metadata as any || {}
  
  if (metadataKey.includes('.')) {
    // nested update for extracted_amounts
    const [parent, child] = metadataKey.split('.')
    if (!currentMetadata[parent]) currentMetadata[parent] = {}
    currentMetadata[parent][child] = newValue
  } else {
    currentMetadata[metadataKey] = newValue
  }

  const { error } = await supabase
    .from('documents')
    .update({ raw_metadata: currentMetadata })
    .eq('id', docId)

  if (error) return { error: error.message }

  const { revalidatePath } = require('next/cache')
  if (doc.matter_id) {
    revalidatePath(\`/matters/\${doc.matter_id}\`)
  }
  
  return { success: true }
}
`

if (!code.includes('export async function updateDocumentMetadata')) {
  code += '\n' + updateFunc
  fs.writeFileSync(file, code)
}
