import assert from 'node:assert/strict'
import test from 'node:test'
import { readFileSync } from 'node:fs'

test('Team is first-class navigation and has a breadcrumb fallback', () => {
  const sidebar = readFileSync(new URL('./SidebarNav.tsx', import.meta.url), 'utf8')
  const breadcrumbs = readFileSync(new URL('./BreadcrumbNav.tsx', import.meta.url), 'utf8')
  const userMenu = readFileSync(new URL('./UserMenu.tsx', import.meta.url), 'utf8')
  assert.match(sidebar, /href: '\/team'.*label: 'Team'/)
  assert.match(breadcrumbs, /'\/team': 'Team'/)
  assert.match(userMenu, /name=\{user\.fullName\}/)
  assert.doesNotMatch(userMenu, /name=\{user\.fullName \|\| user\.email\}/)
})
