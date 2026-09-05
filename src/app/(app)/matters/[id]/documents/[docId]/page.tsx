import { permanentRedirect } from 'next/navigation'

import { canonicalDocumentPath } from '@/lib/canonical-document-route'

export default async function LegacyMatterDocumentPage(props: { params: Promise<{ id: string; docId: string }> }) {
  const { id, docId } = await props.params
  permanentRedirect(canonicalDocumentPath(docId, { matterId: id }))
}
