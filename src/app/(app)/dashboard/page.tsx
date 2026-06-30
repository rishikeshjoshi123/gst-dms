import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import {
  FileText,
  FolderOpen,
  Clock,
  TrendingUp,
  ArrowUpRight,
} from 'lucide-react'
import type { Metadata } from 'next'

export const metadata: Metadata = { title: 'Dashboard' }

async function getDashboardStats(orgId: string) {
  const supabase = await createClient()

  const [clients, matters, documents] = await Promise.all([
    supabase.from('clients').select('id', { count: 'exact', head: true }).eq('org_id', orgId),
    supabase.from('matters').select('id', { count: 'exact', head: true }).eq('org_id', orgId),
    supabase.from('documents').select('id', { count: 'exact', head: true }).eq('org_id', orgId),
  ])

  return {
    clients: clients.count ?? 0,
    matters: matters.count ?? 0,
    documents: documents.count ?? 0,
  }
}

export default async function DashboardPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const cookieStore = await cookies()
  const orgId = cookieStore.get('current_org_id')?.value
  if (!orgId) redirect('/onboarding')

  const [stats, { data: org }] = await Promise.all([
    getDashboardStats(orgId),
    supabase.from('organisations').select('name').eq('id', orgId).single(),
  ])

  const firstName = user.user_metadata?.full_name?.split(' ')[0] ?? 'there'
  const hour = new Date().getHours()
  const greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening'

  const statCards = [
    {
      label: 'Active Clients',
      value: stats.clients,
      icon: FolderOpen,
      href: '/clients',
      color: 'text-[--accent]',
      bg: 'bg-[--accent-muted]',
    },
    {
      label: 'Open Matters',
      value: stats.matters,
      icon: TrendingUp,
      href: '/matters',
      color: 'text-[--success]',
      bg: 'bg-[--success-muted]',
    },
    {
      label: 'Documents',
      value: stats.documents,
      icon: FileText,
      href: '/clients',
      color: 'text-[--warning]',
      bg: 'bg-[--warning-muted]',
    },
    {
      label: 'Pending Review',
      value: 0,
      icon: Clock,
      href: '/clients',
      color: 'text-[--danger]',
      bg: 'bg-[--danger-muted]',
    },
  ]

  return (
    <div className="max-w-5xl mx-auto px-8 py-8">
      {/* Page header */}
      <div className="mb-8 animate-fade-in">
        <h1 className="text-2xl font-bold text-[--text-primary]">
          {greeting}, {firstName} 👋
        </h1>
        <p className="mt-1 text-sm text-[--text-muted]">
          Welcome to <span className="text-[--text-secondary] font-medium">{org?.name}</span> workspace
        </p>
      </div>

      {/* Stat cards */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4 mb-8 animate-fade-in">
        {statCards.map(({ label, value, icon: Icon, href, color, bg }) => (
          <a
            key={label}
            href={href}
            className="group flex flex-col gap-3 p-5 rounded-[--radius-lg] bg-[--bg-surface] border border-[--border-subtle] hover:border-[--border-default] transition-all duration-[--duration-base]"
          >
            <div className="flex items-center justify-between">
              <div className={`flex h-9 w-9 items-center justify-center rounded-[--radius-md] ${bg}`}>
                <Icon size={18} className={color} />
              </div>
              <ArrowUpRight size={14} className="text-[--text-disabled] group-hover:text-[--text-muted] transition-colors" />
            </div>
            <div>
              <p className="text-2xl font-bold text-[--text-primary]">{value}</p>
              <p className="text-xs text-[--text-muted] mt-0.5">{label}</p>
            </div>
          </a>
        ))}
      </div>

      {/* Getting started panel */}
      {stats.clients === 0 && (
        <div className="rounded-[--radius-xl] bg-[--bg-surface] border border-[--border-default] p-8 text-center animate-fade-in">
          <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-[--accent-muted]">
            <FileText size={24} className="text-[--accent]" />
          </div>
          <h2 className="text-lg font-semibold text-[--text-primary]">Ready to track your first case?</h2>
          <p className="mt-2 text-sm text-[--text-muted] max-w-sm mx-auto">
            Add a client and create a matter to start uploading GST proceedings documents and building your case timeline.
          </p>
          <div className="mt-6 flex justify-center gap-3">
            <a
              href="/clients"
              className="inline-flex items-center gap-2 px-5 py-2.5 rounded-[--radius-md] bg-[--accent] text-white text-sm font-medium hover:bg-[--accent-hover] transition-colors"
            >
              Add your first client
              <ArrowUpRight size={14} />
            </a>
          </div>
        </div>
      )}

      {/* Activity placeholder — Phase 14 fills this in */}
      {stats.clients > 0 && (
        <div className="rounded-[--radius-xl] bg-[--bg-surface] border border-[--border-subtle] p-6 animate-fade-in">
          <h2 className="text-sm font-semibold text-[--text-primary] mb-4">Recent Activity</h2>
          <p className="text-sm text-[--text-muted]">
            Activity feed coming in a later phase.
          </p>
        </div>
      )}
    </div>
  )
}
