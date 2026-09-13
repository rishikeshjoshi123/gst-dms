'use client'
import { Button } from '@/components/ui/button'
export default function ReviewError({ unstable_retry }: { error: Error & { digest?: string }; unstable_retry: () => void }) {
  return <section className="p-6"><h1 className="text-page-title">Review</h1><p role="alert" className="my-4">Review could not be loaded. Please try again.</p><Button onClick={unstable_retry}>Retry Review</Button></section>
}
