import { permanentRedirect } from 'next/navigation'

import { documentHubPath } from '@/lib/document-hub-route'

interface InboxPageProps {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}

export default async function InboxPage({ searchParams }: InboxPageProps) {
  permanentRedirect(documentHubPath(await searchParams))
}
