import { getClients } from '@/lib/actions/client'
import { ClientsClientView } from './ClientsClientView'

export const metadata = { title: 'Clients — GST Litigation DMS' }

export default async function ClientsPage() {
  const clients = await getClients()

  return <ClientsClientView clients={clients} />
}
