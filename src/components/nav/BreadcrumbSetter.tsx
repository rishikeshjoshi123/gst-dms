'use client'

import { useEffect } from 'react'
import { useBreadcrumbs, BreadcrumbItem } from './BreadcrumbContext'

export function BreadcrumbSetter({ breadcrumbs }: { breadcrumbs: BreadcrumbItem[] }) {
  const { setBreadcrumbs } = useBreadcrumbs()

  useEffect(() => {
    setBreadcrumbs(breadcrumbs)
  }, [setBreadcrumbs, breadcrumbs])

  return null
}
