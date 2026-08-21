'use client'

import Link from 'next/link'
import { ArrowLeft, FileText, Network, Clock, ShieldCheck } from 'lucide-react'
import { ThemeToggle } from '@/components/nav/ThemeToggle'

const HIGHLIGHT_POINTS = [
  {
    icon: FileText,
    title: 'Smart Document Parsing',
    desc: 'Extract GSTINs, financial years, notice reference numbers, and demand amounts automatically upon upload.',
  },
  {
    icon: Network,
    title: 'Visual Case Timelines',
    desc: 'See how every Show Cause Notice, reply, and adjudication order connects in a visual case graph.',
  },
  {
    icon: Clock,
    title: 'Automated Deadline Alerts',
    desc: 'Never miss an appeal window or hearing date with proactive automated due date tracking.',
  },
]

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-screen w-full overflow-hidden bg-[var(--bg)]">
      {/* ── Left Brand Panel (Simple, Theme-Aware, Clean) ─────────── */}
      <div className="hidden lg:flex w-[380px] xl:w-[420px] shrink-0 relative flex-col justify-between p-10 bg-[var(--surface)] border-r border-[var(--border)] text-[var(--text-primary)]">
        {/* Top — Brand Header */}
        <div>
          <Link href="/" className="inline-flex items-center mb-2 group">
            <span className="text-xl font-extrabold tracking-tight text-[var(--text-primary)]">
              CaseChain
            </span>
          </Link>
          <p className="text-xs text-[var(--text-secondary)] font-medium leading-relaxed">
            GST Litigation Document Management System
          </p>
        </div>

        {/* Center — Clean Feature Highlights */}
        <div className="my-auto py-6 space-y-6">
          <div className="mb-2">
            <h2 className="text-lg font-bold text-[var(--text-primary)] mb-1">
              Organize Your Litigation Practice
            </h2>
            <p className="text-xs text-[var(--text-secondary)] leading-relaxed font-medium">
              Built specifically for tax advocates and legal teams to manage Indirect Tax proceedings without folder chaos.
            </p>
          </div>

          <div className="space-y-4">
            {HIGHLIGHT_POINTS.map((item, idx) => {
              const Icon = item.icon
              return (
                <div key={idx} className="flex items-start gap-3 p-3.5 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg)] shadow-xs">
                  <div className="w-8 h-8 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] flex items-center justify-center shrink-0">
                    <Icon size={16} className="text-[var(--primary)]" />
                  </div>
                  <div>
                    <h3 className="text-xs font-bold text-[var(--text-primary)] mb-0.5">{item.title}</h3>
                    <p className="text-[11px] text-[var(--text-secondary)] leading-relaxed font-medium">{item.desc}</p>
                  </div>
                </div>
              )
            })}
          </div>
        </div>

        {/* Bottom — Clean Security Note */}
        <div className="pt-4 border-t border-[var(--border)] flex items-center justify-between text-[11px] text-[var(--text-muted)] font-medium">
          <span className="flex items-center gap-1.5 text-[var(--success)] font-bold">
            <ShieldCheck size={14} />
            Secure Legal Workspace
          </span>
          <span>© 2026 CaseChain</span>
        </div>
      </div>

      {/* ── Right Main Form Panel ─────────────────────────────────── */}
      <div className="flex-1 flex flex-col min-h-0 overflow-y-auto bg-[var(--bg)]">
        {/* Top bar — back to home button + theme toggle */}
        <div className="flex items-center justify-between px-6 py-4 shrink-0">
          <Link
            href="/"
            className="inline-flex min-h-11 items-center gap-1.5 text-xs font-semibold text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors px-3 py-1.5 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] shadow-xs"
          >
            <ArrowLeft size={14} />
            <span>Back to Home</span>
          </Link>
          <ThemeToggle />
        </div>

        {/* Center Form Card Container */}
        <div className="flex-1 flex items-center justify-center px-4 sm:px-6 py-8">
          <div className="w-full max-w-md">
            {/* Logo for mobile */}
            <div className="flex lg:hidden items-center justify-center mb-6">
              <span className="text-lg font-bold text-[var(--text-primary)]">CaseChain</span>
            </div>

            {/* Form card */}
            <div className="rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] p-8 shadow-sm animate-fade-in">
              {children}
            </div>

            <p className="text-center text-xs text-[var(--text-muted)] font-medium mt-6">
              CaseChain · GST Litigation Document Management System
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}
