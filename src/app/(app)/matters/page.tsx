import { getMatters } from '@/lib/actions/matter'
import { MattersClientView } from './MattersClientView'

export const metadata = { title: 'Matters — GST Litigation DMS' }

export default async function MattersPage() {
  const matters = await getMatters()

  return <MattersClientView matters={matters} />
}
