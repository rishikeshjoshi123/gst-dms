import assert from 'node:assert/strict'
import test from 'node:test'
import { readFile } from 'node:fs/promises'
import { PILOT_RELEASE_MANIFEST, unresolvedPilotApprovals } from './pilot-release-manifest'

test('the pilot manifest records the settled entry and AI boundaries', () => {
  assert.equal(PILOT_RELEASE_MANIFEST.entry.signup, 'invitation_intent_and_matching_verified_email')
  assert.equal(PILOT_RELEASE_MANIFEST.entry.publicOrganisationCreation, 'disabled')
  assert.equal(PILOT_RELEASE_MANIFEST.entry.concurrentCurrentOrganisations, 1)
  assert.equal(PILOT_RELEASE_MANIFEST.capabilities.caseBriefGeneration, 'disabled')
  assert.equal(PILOT_RELEASE_MANIFEST.capabilities.generatedAnswers, 'disabled')
  assert.equal(PILOT_RELEASE_MANIFEST.capabilities.agents, 'disabled')
  assert.ok(PILOT_RELEASE_MANIFEST.routes.developmentOnly.includes('/usage'))
})

test('retention policy is approved while production purge workers remain release-gated', () => {
  assert.deepEqual(unresolvedPilotApprovals(), [])
  assert.equal(PILOT_RELEASE_MANIFEST.capabilities.automaticRetention, 'enabled')
  assert.equal(PILOT_RELEASE_MANIFEST.capabilities.permanentPurge, 'enabled')
  assert.deepEqual(PILOT_RELEASE_MANIFEST.workers.approvalRequired, [
    'dispatch-trash-permanent-delete',
    'reconcile-trash-permanent-delete',
  ])
})

test('the retired 24-hour Trash attention projection is not surfaced on Dashboard', async () => {
  const [page, content] = await Promise.all([
    readFile(new URL('../app/(app)/dashboard/page.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../app/(app)/dashboard/DashboardContent.tsx', import.meta.url), 'utf8'),
  ])
  assert.doesNotMatch(page, /getTrashRetentionTeamAttention|trashRetentionAttention/)
  assert.doesNotMatch(content, /TrashRetentionTeamAttentionPanel|trashRetentionAttention/)
})

test('the manifest fixes the approved PDF and storage envelope', () => {
  assert.deepEqual(PILOT_RELEASE_MANIFEST.limits.acceptedMimeTypes, ['application/pdf'])
  assert.equal(PILOT_RELEASE_MANIFEST.limits.maximumFileBytes, 25 * 1024 * 1024)
  assert.equal(PILOT_RELEASE_MANIFEST.limits.pilotOrganisationUniqueAssetBytes, 350 * 1024 * 1024)
  assert.equal(PILOT_RELEASE_MANIFEST.dataPolicy.preproduction, 'synthetic_or_sanitised_only')
  assert.equal(PILOT_RELEASE_MANIFEST.dataPolicy.production, 'authorised_design_partner_documents_only')
})

test('deployment identity is supplied by named environment inputs, not committed values', () => {
  assert.deepEqual(PILOT_RELEASE_MANIFEST.requiredDeploymentIdentity, {
    environmentVariable: 'CASECHAIN_RELEASE_ENVIRONMENT',
    organisationVariable: 'CASECHAIN_PILOT_ORGANISATION_ID',
    revisionVariable: 'CASECHAIN_RELEASE_REVISION',
  })
})
