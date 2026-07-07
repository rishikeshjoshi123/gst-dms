const fs = require('fs')
const path = require('path')

const file = path.join(__dirname, 'src/app/(app)/inbox/InboxClientView.tsx')
let code = fs.readFileSync(file, 'utf8')

// Add import
if (!code.includes('reprocessDocument')) {
  code = code.replace("import { Trash2, Link as LinkIcon, RefreshCw", "import { Trash2, Link as LinkIcon, RefreshCw, RotateCcw")
  code = code.replace("import { deleteStagedDocument, reevaluateStagedDocuments }", "import { deleteStagedDocument, reevaluateStagedDocuments }\nimport { reprocessDocument } from '@/lib/actions/reprocess'")
}

// Add state
if (!code.includes('isReprocessing')) {
  code = code.replace("const [isPending, startTransition] = useTransition()", "const [isPending, startTransition] = useTransition()\n  const [isReprocessing, setIsReprocessing] = useState<string | null>(null)")
}

// Add handleReprocess
if (!code.includes('handleReprocess')) {
  const func = `
  const handleReprocess = async (docId: string) => {
    setIsReprocessing(docId)
    const res = await reprocessDocument(docId, true)
    setIsReprocessing(null)
    if (res.error) alert(res.error)
  }
  `
  code = code.replace("const handleDelete = async", func + "\n  const handleDelete = async")
}

// Add button to the card header
const searchStr = `<Button variant="ghost" size="sm" onClick={() => window.open(supabase.storage.from('documents').getPublicUrl(selectedDoc.file_path).data.publicUrl, '_blank')} className="h-8 text-xs shrink-0">
                    <ExternalLink size={14} className="mr-1.5" />
                    Original PDF
                  </Button>`
const replaceStr = `<Button variant="outline" size="sm" onClick={() => handleReprocess(selectedDoc.id)} disabled={isReprocessing === selectedDoc.id} className="h-8 text-xs shrink-0 mr-2">
                    {isReprocessing === selectedDoc.id ? <RotateCcw size={14} className="mr-1.5 animate-spin" /> : <RotateCcw size={14} className="mr-1.5" />}
                    Reprocess
                  </Button>\n                  ` + searchStr
code = code.replace(searchStr, replaceStr)

fs.writeFileSync(file, code)
console.log('patched')
