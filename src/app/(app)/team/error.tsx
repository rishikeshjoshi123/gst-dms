'use client'

import { Button } from '@/components/ui/button'

export default function TeamError({ unstable_retry }: { error: Error & { digest?: string }; unstable_retry: () => void }) {
  return <div className="flex min-h-0 flex-1 items-center justify-center p-8 text-center"><div><h1 className="text-page-title text-[var(--text-primary)]">Team unavailable</h1><p className="mt-2 text-body text-[var(--text-muted)]">The directory could not be loaded. Please try again.</p><Button className="mt-4" onClick={unstable_retry}>Try again</Button></div></div>
}
