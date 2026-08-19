'use client'

import { useState, useEffect, useTransition } from 'react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { getClients } from '@/lib/actions/client'
import { getMatters } from '@/lib/actions/matter'
import { reassignDocumentMatter } from '@/lib/actions/document'
import { Search, Loader2, Check } from 'lucide-react'
import { toast } from 'sonner'

export function ReassignDocumentDialog({
  isOpen,
  onClose,
  documentId,
  currentMatterId
}: {
  isOpen: boolean
  onClose: () => void
  documentId: string
  currentMatterId: string
}) {
  const [clients, setClients] = useState<any[]>([])
  const [matters, setMatters] = useState<any[]>([])
  
  const [selectedClientId, setSelectedClientId] = useState<string | null>(null)
  const [selectedMatterId, setSelectedMatterId] = useState<string | null>(null)
  const [isCopyMode, setIsCopyMode] = useState(false)
  
  const [clientSearch, setClientSearch] = useState('')
  const [matterSearch, setMatterSearch] = useState('')
  
  const [isPending, startTransition] = useTransition()
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    if (isOpen) {
      loadData()
    }
  }, [isOpen])

  const loadData = async () => {
    setIsLoading(true)
    const [fetchedClients, fetchedMatters] = await Promise.all([
      getClients(),
      getMatters()
    ])
    setClients(fetchedClients)
    setMatters(fetchedMatters)
    
    // Set initial client based on current matter
    const currentMatter = fetchedMatters.find(m => m.id === currentMatterId)
    if (currentMatter) {
      setSelectedClientId(currentMatter.client_id)
    } else {
      setSelectedClientId(null)
    }
    
    setSelectedMatterId(null)
    setClientSearch('')
    setMatterSearch('')
    setIsLoading(false)
  }

  const handleReassign = () => {
    if (!selectedMatterId) return

    startTransition(async () => {
      const res = await reassignDocumentMatter(documentId, selectedMatterId, isCopyMode ? 'copy' : 'move')
      if ('error' in res) {
        toast.error(res.error)
      } else {
        toast.success(`Document ${isCopyMode ? 'copied' : 'reassigned'} successfully`)
        onClose()
        // The server action handles revalidation so the UI will update
      }
    })
  }

  const filteredClients = clients.filter(c => c.name.toLowerCase().includes(clientSearch.toLowerCase()))
  
  // If a client is selected, show only their matters. Otherwise show all matters.
  const availableMatters = selectedClientId 
    ? matters.filter(m => m.client_id === selectedClientId)
    : matters
    
  const filteredMatters = availableMatters.filter(m => 
    m.title.toLowerCase().includes(matterSearch.toLowerCase()) || 
    (m.matter_code && m.matter_code.toLowerCase().includes(matterSearch.toLowerCase()))
  )

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-md bg-[var(--surface)] border-[var(--border)] p-6 shadow-xl">
        <DialogHeader>
          <DialogTitle className="text-xl text-[var(--text-primary)]">Reassign Document</DialogTitle>
          <DialogDescription className="text-[var(--text-secondary)]">
            Move this document to a different client or matter.
          </DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="animate-spin text-[var(--primary)]" size={24} />
          </div>
        ) : (
          <div className="flex flex-col gap-6 py-4 animate-in fade-in zoom-in-95 duration-200">
            {/* Client Selection */}
            <div className="flex flex-col gap-2">
              <Label className="text-[13px] text-[var(--text-primary)] font-medium">1. Select Client (Optional)</Label>
              <div className="relative">
                <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" />
                <Input 
                  placeholder="Search clients..." 
                  value={clientSearch}
                  onChange={(e) => setClientSearch(e.target.value)}
                  className="pl-9 h-9 text-[13px] bg-[var(--surface)] border-[var(--border)] focus-visible:ring-[var(--primary)]"
                />
              </div>
              
              <div className="flex flex-col border border-[var(--border)] rounded-md overflow-hidden max-h-[140px] overflow-y-auto custom-scrollbar mt-1 bg-[var(--surface-hover)]">
                {filteredClients.length === 0 ? (
                  <div className="p-3 text-[12px] text-[var(--text-muted)] text-center">No clients found</div>
                ) : (
                  filteredClients.map(client => (
                    <button
                      key={client.id}
                      onClick={() => setSelectedClientId(client.id)}
                      className={`flex items-center justify-between text-left px-3 py-2 text-[13px] transition-colors ${
                        selectedClientId === client.id 
                          ? 'bg-[var(--primary)]/10 text-[var(--primary)] font-medium border-l-2 border-[var(--primary)]' 
                          : 'text-[var(--text-secondary)] hover:bg-[var(--surface)] border-l-2 border-transparent'
                      }`}
                    >
                      <span className="truncate pr-2">{client.name}</span>
                      {selectedClientId === client.id && <Check size={14} className="shrink-0" />}
                    </button>
                  ))
                )}
              </div>
            </div>

            {/* Matter Selection */}
            <div className="flex flex-col gap-2">
              <Label className="text-[13px] text-[var(--text-primary)] font-medium">2. Select Matter</Label>
              <div className="relative">
                <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" />
                <Input 
                  placeholder="Search matters..." 
                  value={matterSearch}
                  onChange={(e) => setMatterSearch(e.target.value)}
                  className="pl-9 h-9 text-[13px] bg-[var(--surface)] border-[var(--border)] focus-visible:ring-[var(--primary)]"
                />
              </div>
              
              <div className="flex flex-col border border-[var(--border)] rounded-md overflow-hidden max-h-[180px] overflow-y-auto custom-scrollbar mt-1 bg-[var(--surface-hover)]">
                {filteredMatters.length === 0 ? (
                  <div className="p-3 text-[12px] text-[var(--text-muted)] text-center">No matters found</div>
                ) : (
                  filteredMatters.map(matter => (
                    <button
                      key={matter.id}
                      onClick={() => setSelectedMatterId(matter.id)}
                      className={`flex flex-col text-left px-3 py-2 transition-colors ${
                        selectedMatterId === matter.id 
                          ? 'bg-[var(--primary)]/10 border-l-2 border-[var(--primary)]' 
                          : 'hover:bg-[var(--surface)] border-l-2 border-transparent'
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <span className={`text-[13px] truncate pr-2 ${selectedMatterId === matter.id ? 'text-[var(--primary)] font-medium' : 'text-[var(--text-primary)]'}`}>
                          {matter.title}
                        </span>
                        {selectedMatterId === matter.id && <Check size={14} className="text-[var(--primary)] shrink-0" />}
                      </div>
                      <span className="text-[11px] text-[var(--text-muted)] mt-0.5">
                        {matter.matter_code} • {matter.financial_year || 'Unknown FY'}
                      </span>
                    </button>
                  ))
                )}
              </div>
            </div>

            {/* Copy Mode Checkbox */}
            <div className="flex items-center gap-2 mt-2 px-1">
              <input
                type="checkbox"
                id="copy-mode"
                checked={isCopyMode}
                onChange={(e) => setIsCopyMode(e.target.checked)}
                className="w-4 h-4 rounded border-[var(--border-strong)] text-[var(--primary)] focus:ring-[var(--primary)] bg-[var(--surface)]"
              />
              <Label htmlFor="copy-mode" className="text-[13px] text-[var(--text-secondary)] font-normal cursor-pointer select-none">
                Copy document (keep original in current matter)
              </Label>
            </div>
          </div>
        )}

        <DialogFooter className="mt-2">
          <Button variant="outline" onClick={onClose} disabled={isPending}>Cancel</Button>
          <Button 
            onClick={handleReassign} 
            disabled={!selectedMatterId || isPending}
            className="bg-blue-600 hover:bg-blue-700 text-white min-w-[100px]"
          >
            {isPending ? <Loader2 size={16} className="animate-spin" /> : isCopyMode ? 'Copy' : 'Move'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
