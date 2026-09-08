import assert from 'node:assert/strict'
import test from 'node:test'
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

test('unresolved retention decisions remain explicit production blockers', () => {
  assert.deepEqual(unresolvedPilotApprovals(), ['automaticRetention', 'permanentPurge'])
  assert.deepEqual(PILOT_RELEASE_MANIFEST.workers.approvalRequired, [
    'project-trash-retention-team-attention',
    'dispatch-trash-permanent-delete',
    'reconcile-trash-permanent-delete',
  ])
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
