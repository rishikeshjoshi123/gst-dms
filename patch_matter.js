const fs = require('fs')
const path = require('path')

const file = path.join(__dirname, 'src/lib/actions/matter.ts')
let code = fs.readFileSync(file, 'utf8')

const importsRegex = /import \{ createClient \} from '@\/lib\/supabase\/server'\nimport \{ getCurrentOrgId \} from '\.\/org'/;
if (!code.includes('import { reevaluateMatterLinks }')) {
  code = code.replace(
    importsRegex,
    `import { createClient } from '@/lib/supabase/server'\nimport { getCurrentOrgId } from './org'\nimport { reevaluateMatterLinks } from './chaining'`
  )
}

const revalFunc = `
export async function autoLinkUnlinkedDocuments(matterId: string) {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation' }
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated' }

  const res = await reevaluateMatterLinks(supabase, matterId, orgId, user.id)
  
  const { revalidatePath } = require('next/cache')
  revalidatePath(\`/matters/\${matterId}\`)
  
  return res
}
`

if (!code.includes('export async function autoLinkUnlinkedDocuments')) {
  code += '\n' + revalFunc
  fs.writeFileSync(file, code)
}
