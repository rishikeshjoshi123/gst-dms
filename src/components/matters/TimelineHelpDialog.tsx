'use client'

import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { HelpCircle, GitCommit, Link2, Link2Off, RefreshCw, EyeOff, Sparkles } from 'lucide-react'

export function TimelineHelpDialog({
  isOpen,
  onClose
}: {
  isOpen: boolean
  onClose: () => void
}) {
  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-[560px] bg-white border border-[#E5E2DC] shadow-xl p-0 overflow-hidden">
        {/* Header */}
        <DialogHeader className="p-6 pb-4 border-b border-[#E5E2DC] bg-[#FAFAF9]">
          <div className="flex items-center gap-3">
            <div className="p-2.5 bg-blue-50 text-[#1D4ED8] rounded-md border border-blue-100">
              <Sparkles size={20} />
            </div>
            <div>
              <DialogTitle className="text-[18px] font-semibold text-[#1C1917]">
                Litigation Graph & Link Rules
              </DialogTitle>
              <DialogDescription className="text-[14px] text-[#78716C] pt-0.5">
                Learn how document relationships are automatically built and manually managed.
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        {/* Content Body */}
        <div className="p-6 flex flex-col gap-5 max-h-[65vh] overflow-y-auto">
          {/* Rule 1: Auto System Chaining */}
          <div className="flex items-start gap-4 p-4 rounded-lg bg-white border border-[#E5E2DC] shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
            <div className="p-2 bg-stone-100 text-[#1C1917] rounded-md shrink-0 mt-0.5">
              <GitCommit size={18} />
            </div>
            <div className="flex flex-col gap-1">
              <h4 className="text-[14px] font-semibold text-[#1C1917]">1. Automatic System Chaining</h4>
              <p className="text-[13px] text-[#78716C] leading-relaxed">
                When new documents are processed, the system extracts notice numbers, CBIC DINs, and proceeding types (e.g. <strong>SCN → Reply → Order</strong>). Documents are automatically chained into timeline threads.
              </p>
            </div>
          </div>

          {/* Rule 2: Manual Link Creation */}
          <div className="flex items-start gap-4 p-4 rounded-lg bg-white border border-[#E5E2DC] shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
            <div className="p-2 bg-blue-50 text-[#1D4ED8] rounded-md shrink-0 mt-0.5">
              <Link2 size={18} />
            </div>
            <div className="flex flex-col gap-1">
              <h4 className="text-[14px] font-semibold text-[#1C1917]">2. Create a Manual Link</h4>
              <p className="text-[13px] text-[#78716C] leading-relaxed">
                To link two unlinked nodes, click and drag a connection line from one document node handle onto another node. Select the relationship type (e.g., <em>Responds to</em>, <em>Challenges</em>) in the popup.
              </p>
            </div>
          </div>

          {/* Rule 3: Manual Link Deletion */}
          <div className="flex items-start gap-4 p-4 rounded-lg bg-white border border-[#E5E2DC] shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
            <div className="p-2 bg-red-50 text-red-600 rounded-md shrink-0 mt-0.5">
              <Link2Off size={18} />
            </div>
            <div className="flex flex-col gap-1">
              <h4 className="text-[14px] font-semibold text-[#1C1917]">3. Delete an Existing Link</h4>
              <p className="text-[13px] text-[#78716C] leading-relaxed">
                To remove an existing link between two nodes, simply <strong>draw a line between those two nodes again</strong>. A deletion dialog will appear asking if you want to remove the link.
              </p>
            </div>
          </div>

          {/* Rule 4: Filters & Re-evaluation */}
          <div className="flex items-start gap-4 p-4 rounded-lg bg-white border border-[#E5E2DC] shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
            <div className="p-2 bg-amber-50 text-amber-700 rounded-md shrink-0 mt-0.5">
              <RefreshCw size={18} />
            </div>
            <div className="flex flex-col gap-1">
              <h4 className="text-[14px] font-semibold text-[#1C1917]">4. Re-evaluate Links</h4>
              <p className="text-[13px] text-[#78716C] leading-relaxed">
                Click <strong>"Re-evaluate Links"</strong> at any time to re-run the automatic chaining engine across all documents in this matter. Use <strong>"Hide Supporting"</strong> to clean up annexures.
              </p>
            </div>
          </div>
        </div>

        {/* Footer */}
        <DialogFooter className="p-4 px-6 border-t border-[#E5E2DC] bg-[#FAFAF9]">
          <Button
            type="button"
            onClick={onClose}
            className="w-full sm:w-auto text-[14px] font-semibold bg-[#1D4ED8] hover:bg-[#1E40AF] text-white shadow-sm"
          >
            Got It
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
