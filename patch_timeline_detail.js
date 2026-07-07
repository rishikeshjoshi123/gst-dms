const fs = require('fs')
const path = require('path')

const file = path.join(__dirname, 'src/components/matters/TimelineDocumentDetail.tsx')
let code = fs.readFileSync(file, 'utf8')

if (!code.includes('reprocessDocument')) {
  code = code.replace("import { useState, useTransition } from 'react'", "import { useState, useTransition } from 'react'\nimport { reprocessDocument } from '@/lib/actions/reprocess'")
}

if (!code.includes('handleReprocess')) {
  code = code.replace("const [isEditingMeta, setIsEditingMeta] = useState(false)", "const [isEditingMeta, setIsEditingMeta] = useState(false)\n  const [isReprocessing, setIsReprocessing] = useState(false)")
  
  const func = `
  const handleReprocess = async () => {
    setIsReprocessing(true)
    const res = await reprocessDocument(doc.id, false)
    setIsReprocessing(false)
    if (res.error) alert(res.error)
  }
  `
  code = code.replace("const handleSaveMeta = async () =>", func + "\n  const handleSaveMeta = async () =>")
}

const searchStr = `<Button variant="ghost" size="icon" onClick={() => window.open(supabase.storage.from('documents').getPublicUrl(doc.file_path).data.publicUrl, '_blank')} className="h-8 w-8 text-[--text-secondary] hover:text-[--text-primary] hover:bg-[--bg-surface-hover]">
            <ExternalLink size={16} />
          </Button>`
const replaceStr = `<Button variant="outline" size="sm" onClick={handleReprocess} disabled={isReprocessing} className="h-8 text-xs shrink-0 mr-2 text-[--text-secondary]">
            {isReprocessing ? <RefreshCw size={14} className="mr-1.5 animate-spin" /> : <RefreshCw size={14} className="mr-1.5" />}
            Reprocess
          </Button>\n          ` + searchStr
code = code.replace(searchStr, replaceStr)

fs.writeFileSync(file, code)
console.log('patched')
