import { Suspense } from 'react'
import { getExactMatter } from '@/lib/trash/exact-resource'
import { notFound } from 'next/navigation'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { TrashReadOnlyStrip } from '@/components/trash/TrashReadOnlyStrip'
import { parseMatterWorkspaceRoute, searchParamEntries } from '@/lib/matters/workspace-route'
import { MatterWorkspaceShell } from '@/components/matters/MatterWorkspaceShell'
import { MatterActiveSection } from '@/components/matters/MatterActiveSection'
import { MatterSectionBoundary } from '@/components/matters/MatterSectionBoundary'
import { MatterSectionLoading } from '@/components/matters/MatterSectionLoading'
import { readMatterWorkspaceCapabilities } from '@/lib/matters/workspace-read'

export const metadata = { title: 'Matter Workspace — GST Litigation DMS' }

export default async function MatterPage(props: { 
  params: Promise<{ id: string }>
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const params = await props.params;
  const searchParams = await props.searchParams;
  const fromReview = searchParams?.from === 'review'
  const exactMatter = await getExactMatter(params.id)

  if (!exactMatter) notFound()
  const isTrashReadOnly = exactMatter.state === 'trash'
  const matter = isTrashReadOnly ? exactMatter.data.record : exactMatter.record
  const capabilities = isTrashReadOnly
    ? { canContribute: false }
    : await readMatterWorkspaceCapabilities()
  const route = parseMatterWorkspaceRoute(searchParams)
  const queryEntries = searchParamEntries(searchParams)

  const breadcrumbs = fromReview
    ? [
        { label: 'Pending Review', href: '/review' },
        { label: matter.clients?.name || 'Unknown', href: `/clients/${matter.client_id}` },
      ]
    : [
        { label: 'Clients', href: '/clients' },
        { label: matter.clients?.name || 'Unknown', href: `/clients/${matter.client_id}` },
      ]

  return (
    <div className="flex h-full min-h-0 flex-1 flex-col overflow-hidden animate-fade-in">
      <BreadcrumbSetter breadcrumbs={breadcrumbs} />
      {isTrashReadOnly && <TrashReadOnlyStrip context={exactMatter.context} />}
      <MatterWorkspaceShell
        matter={matter}
        section={route.section}
        queryEntries={queryEntries}
        readOnly={isTrashReadOnly}
      >
        <MatterSectionBoundary section={route.section}>
          <Suspense key={route.section} fallback={<MatterSectionLoading section={route.section} />}>
            <MatterActiveSection
              matterId={params.id}
              exactMatter={exactMatter}
              route={route}
              queryEntries={queryEntries}
              canContribute={capabilities.canContribute}
            />
          </Suspense>
        </MatterSectionBoundary>
      </MatterWorkspaceShell>
    </div>
  )
}
