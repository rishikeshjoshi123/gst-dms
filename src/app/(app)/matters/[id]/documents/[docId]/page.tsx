import { permanentRedirect } from 'next/navigation'

import { legacyCanonicalDocumentRedirectPath } from '@/lib/canonical-document-route'

export default async function LegacyMatterDocumentPage(props: {
  params: Promise<{ id: string; docId: string }>
  searchParams: Promise<{ version?: string | string[]; page?: string | string[] }>
}) {
  const [{ id, docId }, query] = await Promise.all([props.params, props.searchParams])
  permanentRedirect(legacyCanonicalDocumentRedirectPath(docId, id, query))
}
