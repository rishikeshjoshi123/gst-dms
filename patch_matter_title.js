const fs = require('fs')
const path = require('path')

const file = path.join(__dirname, 'src/lib/actions/matter.ts')
let code = fs.readFileSync(file, 'utf8')

const updateTitleFunc = `
export async function updateMatterTitle(matterId: string, newTitle: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }

  const { error } = await supabase
    .from('matters')
    .update({ title: newTitle })
    .eq('id', matterId)
    .eq('org_id', orgId)

  if (error) return { error: error.message }

  const { revalidatePath } = require('next/cache')
  revalidatePath(\`/matters/\${matterId}\`)
  
  return { success: true }
}
`

if (!code.includes('export async function updateMatterTitle')) {
  code += '\n' + updateTitleFunc
  fs.writeFileSync(file, code)
}
