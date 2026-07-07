const fs = require('fs')
const path = require('path')

const file = path.join(__dirname, 'src/components/matters/TimelineGraph.tsx')
let code = fs.readFileSync(file, 'utf8')

// Add imports
if (!code.includes('autoLinkUnlinkedDocuments')) {
  code = code.replace(
    "import { Button } from '@/components/ui/button'",
    "import { Button } from '@/components/ui/button'\nimport { autoLinkUnlinkedDocuments } from '@/lib/actions/matter'\nimport { useTransition } from 'react'\nimport { Loader2, RefreshCw } from 'lucide-react'"
  )
}

// Add matterId and transition state
const signatureRegex = /export function TimelineGraph\(\{[\s\S]*?\}\) \{/
if (!code.includes('const [isPending, startTransition] = useTransition()')) {
  // we need matterId, let's extract it from the first document's matter_id
  code = code.replace(
    '  const [compact, setCompact] = useState(false)',
    `  const [compact, setCompact] = useState(false)
  const [isPending, startTransition] = useTransition()
  const matterId = documents.length > 0 ? documents[0].matter_id : null;
  
  const handleReevaluate = () => {
    if (!matterId) return;
    startTransition(async () => {
      const res = await autoLinkUnlinkedDocuments(matterId);
      if (res.error) alert(res.error);
    });
  };
`
  )
}

// Add the button next to the Unlinked Documents header
const unlinkedHeaderRegex = /<h3 className="text-sm font-semibold text-\[--text-secondary\] uppercase tracking-wider">Unlinked Documents<\/h3>\s*<Badge variant="muted" className="ml-2">\{unlinked\.length\}<\/Badge>/

const newHeader = `<div className="flex-1 flex items-center gap-2">
                    <h3 className="text-sm font-semibold text-[--text-secondary] uppercase tracking-wider">Unlinked Documents</h3>
                    <Badge variant="muted" className="ml-2">{unlinked.length}</Badge>
                  </div>
                  <Button 
                    variant="outline" 
                    size="sm" 
                    onClick={handleReevaluate} 
                    disabled={isPending}
                    className="h-8 text-xs shrink-0"
                  >
                    {isPending ? <Loader2 size={12} className="animate-spin mr-1.5" /> : <RefreshCw size={12} className="mr-1.5" />}
                    Re-evaluate Links
                  </Button>`

if (!code.includes('handleReevaluate')) {
  code = code.replace(unlinkedHeaderRegex, newHeader)
  code = code.replace(
    '<div className="flex items-center gap-2 mb-4">',
    '<div className="flex items-center justify-between gap-2 mb-4 w-full">'
  )
  fs.writeFileSync(file, code)
}

