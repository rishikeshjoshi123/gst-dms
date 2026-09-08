import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { isLegacyUsageDevelopmentEnvironment } from './legacy-usage-boundary'

const usagePageSource = readFileSync(
  new URL('../../app/(app)/usage/page.tsx', import.meta.url),
  'utf8',
)
const pricingActionSource = readFileSync(
  new URL('../actions/pricing.ts', import.meta.url),
  'utf8',
)
const layoutSource = readFileSync(
  new URL('../../app/(app)/layout.tsx', import.meta.url),
  'utf8',
)

test('legacy usage tooling is enabled only in development', () => {
  assert.equal(isLegacyUsageDevelopmentEnvironment('development'), true)
  assert.equal(isLegacyUsageDevelopmentEnvironment('production'), false)
  assert.equal(isLegacyUsageDevelopmentEnvironment('test'), false)
  assert.equal(isLegacyUsageDevelopmentEnvironment(undefined), false)
})

test('route and pricing action enforce the boundary before privileged clients', () => {
  const routeGuard = usagePageSource.indexOf('isLegacyUsageDevelopmentEnvironment()')
  const routeServiceClient = usagePageSource.indexOf('createServiceClient()')
  assert.ok(routeGuard >= 0 && routeGuard < routeServiceClient)

  const actionGuard = pricingActionSource.indexOf('isLegacyUsageDevelopmentEnvironment()')
  const actionServiceClient = pricingActionSource.indexOf('createServiceClient()')
  assert.ok(actionGuard >= 0 && actionGuard < actionServiceClient)
  assert.match(usagePageSource, /if \(!isLegacyUsageDevelopmentEnvironment\(\)\) notFound\(\)/)
})

test('tenant navigation receives the same development-only decision', () => {
  assert.match(layoutSource, /showDevelopmentUsage=\{isLegacyUsageDevelopmentEnvironment\(\)\}/)
})
