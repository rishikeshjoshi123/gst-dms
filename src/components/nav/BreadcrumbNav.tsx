'use client'

import React from 'react'
import Link from 'next/link'
import { ChevronRight } from 'lucide-react'
import { useBreadcrumbs } from './BreadcrumbContext'
import { usePathname } from 'next/navigation'

const fallbackLabels: Record<string, string> = {
  '/dashboard': 'Dashboard',
  '/inbox': 'Document Hub',
  '/clients': 'Clients',
  '/matters': 'Matters',
  '/notes': 'Notes',
  '/review': 'Pending Review',
  '/notifications': 'Notifications',
  '/usage': 'Token Usage',
  '/settings': 'Settings',
  '/dev/design-system': 'Design system',
}

export function BreadcrumbNav() {
  const { breadcrumbs } = useBreadcrumbs()
  const pathname = usePathname()
  const fallbackLabel = fallbackLabels[pathname] ?? 'CaseChain'

  return (
    <div className="flex items-center text-[13px] font-semibold text-[var(--text-muted)] gap-2">
      {breadcrumbs.length === 0 ? (
        <span className="text-[var(--text-primary)] font-bold tracking-tight text-base">{fallbackLabel}</span>
      ) : (
        breadcrumbs.map((item, index) => (
          <React.Fragment key={index}>
            {index > 0 && <ChevronRight size={14} className="text-[var(--text-disabled)]" />}
            {item.href ? (
              <Link href={item.href} className="hover:text-[var(--primary)] transition-colors">
                {item.label}
              </Link>
            ) : (
              <span className="text-[var(--text-primary)] font-bold">{item.label}</span>
            )}
          </React.Fragment>
        ))
      )}
    </div>
  )
}
