import assert from 'node:assert/strict'
import test from 'node:test'
import { PILOT_RELEASE_MANIFEST } from './pilot-release-manifest'
import { evaluatePilotReleasePreflight } from './pilot-release-preflight'

test('release matrix readiness passes while confidential production remains intentionally blocked', () => {
  const result = evaluatePilotReleasePreflight()

  assert.equal(result.releaseMatrixReady, true)
  assert.equal(result.confidentialProductionReady, false)
  assert.deepEqual(result.releaseMatrixFailures, [])
  assert.deepEqual(result.confidentialProductionBlockers, [
    'exact revision and environment identity is not verified',
    'goLive ownership is unassigned',
    'rollback ownership is unassigned',
    'support ownership is unassigned',
    'incident ownership is unassigned',
    'compliant production host is not verified',
    'database and private Storage recovery drill is not verified',
    'provider and deployed acceptance is not verified',
  ])
})

test('verified identity state still fails closed when deployment identity inputs are absent', () => {
  const manifest = {
    ...PILOT_RELEASE_MANIFEST,
    confidentialDeploymentGates: {
      ...PILOT_RELEASE_MANIFEST.confidentialDeploymentGates,
      exactRevisionAndEnvironmentIdentity: 'verified' as const,
    },
  }

  const result = evaluatePilotReleasePreflight(manifest)
  assert.equal(result.confidentialProductionReady, false)
  assert.ok(result.confidentialProductionBlockers.includes('release environment identity is absent or invalid'))
  assert.ok(result.confidentialProductionBlockers.includes('pilot organisation identity is absent or invalid'))
  assert.ok(result.confidentialProductionBlockers.includes('release revision identity is absent or invalid'))
})

test('production readiness only opens when every external confidential-data gate and identity are evidenced', () => {
  const manifest = {
    ...PILOT_RELEASE_MANIFEST,
    confidentialDeploymentGates: {
      exactRevisionAndEnvironmentIdentity: 'verified' as const,
      ownership: { goLive: 'named', rollback: 'named', support: 'named', incident: 'named' },
      compliantHost: 'verified' as const,
      databaseAndPrivateStorageRecovery: 'verified' as const,
      providerAndDeployedAcceptance: 'verified' as const,
    },
  }

  const result = evaluatePilotReleasePreflight(manifest, {
    environment: 'production',
    organisationId: '05f7d867-7a90-4b42-9e14-722ea7d418b4',
    revision: 'a4aa6f05e72e5f9ee538bdcb5400f4c3660e0be0',
  })
  assert.equal(result.releaseMatrixReady, true)
  assert.equal(result.confidentialProductionReady, true)
  assert.deepEqual(result.confidentialProductionBlockers, [])
})
