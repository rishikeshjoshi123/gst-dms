'use client'

import { useState, useTransition } from 'react'
import { createMatter } from '@/lib/actions/matter'
import { FINANCIAL_YEARS } from '@/lib/constants'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { FormField } from '@/components/ui/label'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Plus } from 'lucide-react'
import { useRouter } from 'next/navigation'

export function NewMatterButton({ clientId }: { clientId: string }) {
  const [open, setOpen] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()
  const router = useRouter()

  function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    const formData = new FormData(e.currentTarget)
    formData.append('client_id', clientId)

    startTransition(async () => {
      const result = await createMatter(formData)
      if (result?.error) {
        setError(result.error)
      } else {
        setOpen(false)
        router.push(`/matters/${result.id}`)
      }
    })
  }

  return (
    <>
      <Button id="new-matter-btn" onClick={() => setOpen(true)}>
        <Plus size={14} />
        New Matter
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Create a new matter</DialogTitle>
          </DialogHeader>

          <form onSubmit={handleSubmit} className="flex flex-col gap-4 mt-2">
            <FormField label="Matter Title" required hint="Cosmetic title for your reference">
              <Input
                id="title"
                name="title"
                type="text"
                placeholder="e.g. FY23-24 Audit Notice"
                autoFocus
                required
                minLength={2}
                disabled={isPending}
              />
            </FormField>

            <FormField label="Financial Year" required>
              <select
                id="financial_year"
                name="financial_year"
                required
                disabled={isPending}
                className="w-full rounded-[--radius-md] border border-[--border-subtle] bg-[--bg-surface] px-3 py-2 text-sm text-[--text-primary] placeholder:text-[--text-muted] focus:border-[--focus-ring] focus:outline-none focus:ring-1 focus:ring-[--focus-ring]"
              >
                <option value="">Select a year...</option>
                {FINANCIAL_YEARS.map(year => (
                  <option key={year} value={year}>{year}</option>
                ))}
              </select>
            </FormField>

            <FormField label="Description">
              <textarea
                id="description"
                name="description"
                placeholder="Optional notes about this matter"
                rows={3}
                disabled={isPending}
                className="w-full rounded-[--radius-md] border border-[--border-subtle] bg-[--bg-surface] px-3 py-2 text-sm text-[--text-primary] placeholder:text-[--text-muted] focus:border-[--focus-ring] focus:outline-none focus:ring-1 focus:ring-[--focus-ring]"
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
                {isPending ? 'Creating…' : 'Create matter'}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </>
  )
}
