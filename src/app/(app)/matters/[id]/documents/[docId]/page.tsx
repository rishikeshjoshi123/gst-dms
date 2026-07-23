import { createClient } from '@/lib/supabase/server'
import { getDocumentSignedUrl, getDocumentsByMatter } from '@/lib/actions/document'
import { getNotes } from '@/lib/actions/notes'
import { notFound } from 'next/navigation'
import { PdfViewer } from '@/components/ui/pdf-viewer'
import { TimelineDocumentDetail } from '@/components/matters/TimelineDocumentDetail'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'

export default async function DocumentPage(props: { params: Promise<{ id: string; docId: string }> }) {
  const params = await props.params;
  const supabase = await createClient()

  const { data: doc } = await supabase
    .from('documents')
    .select(`
      *,
      matters(id, title)
    `)
    .eq('id', params.docId)
    .eq('matter_id', params.id)
    .single()

  if (!doc) {
    notFound()
  }

  const { url, error } = await getDocumentSignedUrl('documents', doc.storage_path)
  const notes = await getNotes({ documentId: params.docId })
  const allDocsData = await getDocumentsByMatter(params.id)
  const allDocuments = [...allDocsData.proceedings, ...allDocsData.supporting]
  const links = allDocsData.links
  
  if (error || !url) {
    return <div className="p-10 text-[var(--danger)]">Failed to load document: {error}</div>
  }

  const breadcrumbs = [
    { label: 'Clients', href: '/clients' },
    { label: doc.matters?.title || 'Matter', href: `/matters/${params.id}` },
    { label: doc.reference_number || doc.storage_path.split('/').pop() || 'Document' }
  ]

  return (
    <div className="flex flex-col flex-1 overflow-hidden gap-4 w-full animate-fade-in">
      <BreadcrumbSetter breadcrumbs={breadcrumbs} />

      <div className="flex items-center gap-4 shrink-0">
        <Link href={`/matters/${params.id}`} className="flex items-center gap-2 text-sm text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors">
          <ArrowLeft size={16} />
          Back to Matter
        </Link>
      </div>
      
      <div className="flex flex-col lg:flex-row gap-6 min-h-0 flex-1">
        {/* PDF Viewer */}
        <div className="w-full lg:w-[65%] h-full rounded-lg border border-[var(--border)] shadow-[var(--shadow-sm)] overflow-hidden bg-white">
          <PdfViewer url={url} />
        </div>

        {/* Document Details Sidebar */}
        <div className="w-full lg:w-[35%] h-full">
          <TimelineDocumentDetail doc={doc} allDocuments={allDocuments} links={links} notes={notes} />
        </div>
      </div>
    </div>
  )
}
