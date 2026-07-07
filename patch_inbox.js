const fs = require('fs')
const path = require('path')

const file = path.join(__dirname, 'src/lib/actions/inbox.ts')
let code = fs.readFileSync(file, 'utf8')

// Add imports for placeDocument
if (!code.includes('import { placeDocument }')) {
  code = code.replace(
    "import { tasks } from '@trigger.dev/sdk/v3'",
    "import { tasks } from '@trigger.dev/sdk/v3'\nimport { placeDocument } from './chaining'\nimport type { AIDocumentResult } from '@/lib/ai/vertex'"
  )
}

// 1. Update assignStagedDocument to call placeDocument
const docInsertRegex = /const \{ data: doc, error: docError \} = await supabase[\s\S]*?if \(docError \|\| !doc\) \{[\s\S]*?return \{ error: docError\?.message \?\? 'Failed to create document record\.' \}\n  \}/;

const placeDocumentInjection = `
  // 2.5 Place document in graph
  if (staged.raw_metadata) {
    const aiResult = staged.raw_metadata as unknown as AIDocumentResult;
    // ensure chaining_attributes exists for placeDocument
    if (!aiResult.chaining_attributes) {
      aiResult.chaining_attributes = {};
    }
    try {
      await placeDocument(supabase, doc.id, matterId, orgId, user.id, aiResult);
    } catch (e) {
      console.error('Failed to link document in graph:', e);
    }
  }
`;

if (!code.includes('// 2.5 Place document in graph')) {
  code = code.replace(docInsertRegex, match => match + '\n' + placeDocumentInjection)
}

// Ensure select includes raw_metadata
code = code.replace(
  ".select('id, storage_path, status')",
  ".select('id, storage_path, status, raw_metadata')"
)

// 2. Update autoCreateClientAndMatterForStagedDocument title generation
const titleGenRegex = /const title = metadata\.reference_number \|\| `Matter for \$\{metadata\.doc_type \|\| 'Document'\}`/;
const newTitleGen = `const docTypeStr = metadata.doc_type || 'Document';
  const fyStr = metadata.financial_year || new Date().getFullYear();
  const title = \`\${docTypeStr} - FY \${fyStr}\`;`;

code = code.replace(titleGenRegex, newTitleGen);

// 3. Add reevaluateStagedDocuments
const reevaluateFunc = `
// ── Re-evaluate Staged Documents ─────────────────────────────────────────

export async function reevaluateStagedDocuments() {
  const supabase = await createClient()
  const orgId = await getCurrentOrgId()
  if (!orgId) return

  const { data: staged } = await supabase
    .from('staged_documents')
    .select('*')
    .eq('org_id', orgId)
    .eq('status', 'needs_review')

  if (!staged || staged.length === 0) return

  let revalidated = false

  for (const doc of staged) {
    const metadata = doc.raw_metadata as any
    if (!metadata) continue

    let clientId: string | null = null
    let gstin: string | null = null

    if (metadata.gstin) {
      let s = metadata.gstin.trim().toUpperCase().replace(/[^A-Z0-9]/g, '')
      if (s.length === 15) {
        let state = s.substring(0, 2).replace(/O/g, '0')
        s = state + s.substring(2)
      }
      gstin = s
    }

    if (gstin) {
      const { data: existingClient } = await supabase
        .from('clients')
        .select('id')
        .eq('org_id', orgId)
        .eq('gstin', gstin)
        .is('deleted_at', null)
        .maybeSingle()
      if (existingClient) clientId = existingClient.id
    } else if (metadata.client_name) {
      const { data: existingClient } = await supabase
        .from('clients')
        .select('id')
        .eq('org_id', orgId)
        .eq('name', metadata.client_name)
        .is('deleted_at', null)
        .maybeSingle()
      if (existingClient) clientId = existingClient.id
    }

    if (clientId) {
      const { data: matters } = await supabase
        .from('matters')
        .select('id')
        .eq('client_id', clientId)
        .eq('status', 'active')

      if (matters && matters.length > 0) {
        await supabase
          .from('staged_documents')
          .update({
            suggested_client_id: clientId,
            suggested_matter_id: matters[0].id,
            suggestion_reason: 'Match found in re-evaluation'
          })
          .eq('id', doc.id)
        revalidated = true
      }
    }
  }

  if (revalidated) {
    revalidatePath('/inbox')
  }
}
`;

if (!code.includes('reevaluateStagedDocuments()')) {
  code += '\n' + reevaluateFunc;
}

fs.writeFileSync(file, code)
