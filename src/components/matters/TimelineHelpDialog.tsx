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
      <DialogContent className="sm:max-w-[560px] bg-[var(--surface)] border border-[var(--border)] shadow-xl p-0 overflow-hidden text-[var(--text-primary)]">
        {/* Header */}
        <DialogHeader className="p-6 pb-4 border-b border-[var(--border)] bg-[var(--bg)]">
          <div className="flex items-center gap-3">
            <div className="p-2.5 bg-[var(--primary)]/10 text-[var(--primary)] rounded-md border border-[var(--primary)]/20">
              <Sparkles size={20} />
            </div>
            <div>
              <DialogTitle className="text-[18px] font-semibold text-[var(--text-primary)]">
                Litigation Graph & Link Rules
              </DialogTitle>
              <DialogDescription className="text-[14px] text-[var(--text-secondary)] pt-0.5">
                Learn how document relationships are automatically built and manually managed.
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        {/* Content Body */}
        <div className="p-6 flex flex-col gap-5 max-h-[65vh] overflow-y-auto">
          {/* Rule 1: Auto System Chaining */}
          <div className="flex items-start gap-4 p-4 rounded-lg bg-[var(--surface)] border border-[var(--border)] shadow-sm">
            <div className="p-2 bg-[var(--bg)] text-[var(--text-primary)] rounded-md shrink-0 mt-0.5 border border-[var(--border)]">
              <GitCommit size={18} />
            </div>
            <div className="flex flex-col gap-1">
              <h4 className="text-[14px] font-semibold text-[var(--text-primary)]">1. Automatic System Chaining</h4>
              <p className="text-[13px] text-[var(--text-secondary)] leading-relaxed">
                When new documents are processed, the system extracts notice numbers, CBIC DINs, and proceeding types (e.g. <strong className="text-[var(--text-primary)]">SCN → Reply → Order</strong>). Documents are automatically chained into timeline threads.
              </p>
            </div>
          </div>

          {/* Rule 2: Manual Link Creation */}
          <div className="flex items-start gap-4 p-4 rounded-lg bg-[var(--surface)] border border-[var(--border)] shadow-sm">
            <div className="p-2 bg-[var(--primary)]/10 text-[var(--primary)] rounded-md shrink-0 mt-0.5 border border-[var(--primary)]/20">
              <Link2 size={18} />
            </div>
            <div className="flex flex-col gap-1">
              <h4 className="text-[14px] font-semibold text-[var(--text-primary)]">2. Create a Manual Link</h4>
              <p className="text-[13px] text-[var(--text-secondary)] leading-relaxed">
                To link two unlinked nodes, click and drag a connection line from one document node handle onto another node. Select the relationship type (e.g., <em>Responds to</em>, <em>Challenges</em>) in the popup.
              </p>
            </div>
          </div>

          {/* Rule 3: Manual Link Deletion */}
          <div className="flex items-start gap-4 p-4 rounded-lg bg-[var(--surface)] border border-[var(--border)] shadow-sm">
            <div className="p-2 bg-[var(--danger-muted)] text-[var(--danger)] rounded-[var(--radius-sm)] shrink-0 mt-0.5 border border-[color-mix(in_srgb,var(--danger)_30%,transparent)]">
              <Link2Off size={18} />
            </div>
            <div className="flex flex-col gap-1">
              <h4 className="text-[14px] font-semibold text-[var(--text-primary)]">3. Delete an Existing Link</h4>
              <p className="text-[13px] text-[var(--text-secondary)] leading-relaxed">
                To remove an existing link between two nodes, simply <strong className="text-[var(--text-primary)]">draw a line between those two nodes again</strong>. A deletion dialog will appear asking if you want to remove the link.
              </p>
            </div>
          </div>

          {/* Rule 4: Filters & Re-evaluation */}
          <div className="flex items-start gap-4 p-4 rounded-lg bg-[var(--surface)] border border-[var(--border)] shadow-sm">
            <div className="p-2 bg-[var(--warning-muted)] text-[var(--warning)] rounded-[var(--radius-sm)] shrink-0 mt-0.5 border border-[color-mix(in_srgb,var(--warning)_30%,transparent)]">
              <RefreshCw size={18} />
            </div>
            <div className="flex flex-col gap-1">
              <h4 className="text-[14px] font-semibold text-[var(--text-primary)]">4. Re-evaluate Links</h4>
              <p className="text-[13px] text-[var(--text-secondary)] leading-relaxed">
                Click <strong className="text-[var(--text-primary)]">"Re-evaluate Links"</strong> at any time to re-run the automatic chaining engine across all documents in this matter. Use <strong className="text-[var(--text-primary)]">"Hide Supporting"</strong> to clean up annexures.
              </p>
            </div>
          </div>
        </div>

        {/* Footer */}
        <DialogFooter className="p-4 px-6 border-t border-[var(--border)] bg-[var(--bg)]">
          <Button
            type="button"
            onClick={onClose}
            className="w-full sm:w-auto text-[14px] font-semibold bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-white shadow-sm"
          >
            Got It
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
