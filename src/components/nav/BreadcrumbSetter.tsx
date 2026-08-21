'use client'

import { useEffect } from 'react'
import { useBreadcrumbs, BreadcrumbItem } from './BreadcrumbContext'

export function BreadcrumbSetter({ breadcrumbs }: { breadcrumbs: BreadcrumbItem[] }) {
  const { setBreadcrumbs } = useBreadcrumbs()
  const serializedBreadcrumbs = JSON.stringify(breadcrumbs)

  useEffect(() => {
    const nextBreadcrumbs = JSON.parse(serializedBreadcrumbs) as BreadcrumbItem[]
    setBreadcrumbs(current => {
      const unchanged = current.length === nextBreadcrumbs.length && current.every((item, index) => (
        item.label === nextBreadcrumbs[index]?.label && item.href === nextBreadcrumbs[index]?.href
      ))
      return unchanged ? current : nextBreadcrumbs
    })
  }, [setBreadcrumbs, serializedBreadcrumbs])

  return null
}
