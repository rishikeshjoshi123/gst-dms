'use client'

import { useRef, useState, useTransition } from 'react'
import { createClientAction } from '@/lib/actions/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { FormField } from '@/components/ui/label'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Plus } from 'lucide-react'
import { useRouter } from 'next/navigation'

export function NewClientButton() {
  const [open, setOpen] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()
  const idempotencyKey = useRef(crypto.randomUUID())
  const router = useRouter()

  function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    const formData = new FormData(e.currentTarget)
    formData.set('idempotencyKey', idempotencyKey.current)

    startTransition(async () => {
      const result = await createClientAction(formData)
      if (result?.error) {
        setError(result.error)
      } else {
        idempotencyKey.current = crypto.randomUUID()
        setOpen(false)
        router.refresh()
      }
    })
  }

  return (
    <>
      <Button id="new-client-btn" onClick={() => setOpen(true)}>
        <Plus size={14} />
        New Client
      </Button>

      <Dialog open={open} onOpenChange={(nextOpen) => {
        if (!nextOpen && !isPending) {
          idempotencyKey.current = crypto.randomUUID()
          setError(null)
        }
        setOpen(nextOpen)
      }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add a new client</DialogTitle>
          </DialogHeader>

          <form onSubmit={handleSubmit} className="flex flex-col gap-4 mt-2">
            <FormField label="Client name" htmlFor="name" required>
              <Input
                id="name"
                name="name"
                type="text"
                placeholder="e.g. Heavy Steel Industries Pvt. Ltd."
                autoFocus
                required
                minLength={2}
                disabled={isPending}
              />
            </FormField>

            <FormField
              label="GSTIN"
              htmlFor="gstin"
              hint="15-character GST Identification Number — used for AI document routing"
            >
              <Input
                id="gstin"
                name="gstin"
                type="text"
                placeholder="e.g. 27AABCH1234F1Z5"
                maxLength={15}
                style={{ textTransform: 'uppercase', fontFamily: 'monospace' }}
                disabled={isPending}
              />
            </FormField>

            <FormField label="PAN" htmlFor="pan">
              <Input
                id="pan"
                name="pan"
                type="text"
                placeholder="e.g. AABCH1234F"
                maxLength={10}
                style={{ textTransform: 'uppercase', fontFamily: 'monospace' }}
                disabled={isPending}
              />
            </FormField>

            {error && (
              <p className="text-sm text-[--danger] rounded-[--radius-md] bg-[--danger-muted] px-3 py-2">
                {error}
              </p>
            )}

            <div className="flex justify-end gap-2 pt-1">
              <Button type="button" variant="secondary" onClick={() => setOpen(false)} disabled={isPending}>
                Cancel
              </Button>
              <Button type="submit" loading={isPending}>
                {isPending ? 'Creating…' : 'Create client'}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </>
  )
}
