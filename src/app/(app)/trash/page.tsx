import type { Metadata } from 'next'

import { getTrashWorkspace } from '@/lib/trash/workspace'
import type { TrashResourceFilter } from '@/lib/trash/workspace-model'
import { TrashWorkspace } from './TrashWorkspace'

export const metadata: Metadata = { title: 'Trash — GST Litigation DMS' }

const resourceFilters = new Set<TrashResourceFilter>(['all', 'client', 'matter', 'document'])
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

function singleValue(value: string | string[] | undefined) {
  return typeof value === 'string' ? value : ''
}

export default async function TrashPage({ searchParams }: PageProps<'/trash'>) {
  const params = await searchParams
  const query = singleValue(params.q).trim().slice(0, 120)
  const requestedType = singleValue(params.type) as TrashResourceFilter
  const resourceType = resourceFilters.has(requestedType) ? requestedType : 'all'
  const requestedSelection = singleValue(params.selected)
  const selectedOperationId = uuidPattern.test(requestedSelection) ? requestedSelection : null
  const data = await getTrashWorkspace({ query, resourceType, selectedOperationId })

  return (
    <TrashWorkspace
      data={data}
      query={query}
      resourceType={resourceType}
    />
  )
}
