import { getNotifications } from '@/lib/actions/notifications'
import { NotificationsClientView } from './NotificationsClientView'
import type { Metadata } from 'next'

export const metadata: Metadata = { title: 'Notifications' }

export default async function NotificationsPage() {
  const { notifications } = await getNotifications()

  return <NotificationsClientView initialNotifications={notifications} />
}
