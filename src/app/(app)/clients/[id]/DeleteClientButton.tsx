'use client'

import { useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { Trash2, AlertTriangle, Loader2 } from 'lucide-react'
import { deleteClientAction } from '@/lib/actions/client'

export function DeleteClientButton({ clientId, clientName }: { clientId: string; clientName: string }) {
  const router = useRouter()
  const [isOpen, setIsOpen] = useState(false)
  const [isDeleting, setIsDeleting] = useState(false)
  const clientTrashIdempotencyKey = useRef<string | null>(null)

  const handleDelete = async () => {
    if (!clientTrashIdempotencyKey.current) {
      clientTrashIdempotencyKey.current = `trash.client.${crypto.randomUUID()}`
    }
    setIsDeleting(true)
    const res = await deleteClientAction(clientId, clientTrashIdempotencyKey.current)
    setIsDeleting(false)

    if (res.error) {
      toast.error(res.error)
    } else {
      clientTrashIdempotencyKey.current = null
      toast.success('Client deleted successfully')
      setIsOpen(false)
      router.push('/clients')
    }
  }

  useEffect(() => {
    clientTrashIdempotencyKey.current = null
  }, [clientId])

  return (
    <>
      <button
        onClick={() => setIsOpen(true)}
        className="inline-flex items-center justify-center rounded-[var(--radius-sm)] text-[13px] font-medium h-9 px-3 bg-[var(--surface)] hover:bg-[var(--danger-muted)] text-[var(--danger)] border border-[color-mix(in_srgb,var(--danger)_30%,transparent)] transition-colors shadow-sm ml-auto"
        title="Delete Client"
      >
        <Trash2 size={14} className="mr-1.5 text-[var(--danger)]" />
        Delete Client
      </button>

      {isOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-fade-in">
          <div className="bg-[var(--surface)] text-[var(--text-primary)] rounded-lg shadow-xl border border-[var(--border)] w-full max-w-md overflow-hidden flex flex-col animate-in zoom-in-95 duration-150">
            <div className="p-6 flex flex-col gap-3">
              <div className="flex items-center gap-3 text-[var(--danger)]">
                <AlertTriangle size={24} className="shrink-0" />
                <h3 className="text-[18px] font-semibold text-[var(--text-primary)]">Delete Client?</h3>
              </div>
              <p className="text-[14px] font-normal text-[var(--text-secondary)] leading-relaxed">
                Are you sure you want to delete <strong className="text-[var(--text-primary)]">"{clientName}"</strong>? This will soft-delete the client, along with all of their matters and documents.
              </p>
            </div>
            <div className="flex items-center justify-end gap-3 p-4 px-6 border-t border-[var(--border)] bg-[var(--bg)]">
              <button
                type="button"
                onClick={() => {
                  clientTrashIdempotencyKey.current = null
                  setIsOpen(false)
                }}
                disabled={isDeleting}
                className="px-4 py-2 text-[14px] font-medium text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] rounded-md transition-colors"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleDelete}
                disabled={isDeleting}
                className="inline-flex items-center justify-center px-5 py-2 text-[14px] font-semibold bg-[var(--danger)] hover:bg-[var(--danger-hover)] text-[var(--on-danger)] rounded-[var(--radius-sm)] transition-colors shadow-sm"
              >
                {isDeleting ? (
                  <>
                    <Loader2 size={16} className="animate-spin mr-2" />
                    Deleting...
                  </>
                ) : (
                  'Delete Client'
                )}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
