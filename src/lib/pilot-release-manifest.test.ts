import assert from 'node:assert/strict'
import test from 'node:test'
import { readFile } from 'node:fs/promises'
import { conditionalPilotCapabilities, PILOT_RELEASE_MANIFEST } from './pilot-release-manifest'

test('the pilot manifest records the settled entry and AI boundaries', () => {
  assert.equal(PILOT_RELEASE_MANIFEST.entry.signup, 'email_verification_then_create_or_join')
  assert.equal(PILOT_RELEASE_MANIFEST.entry.publicOrganisationCreation, 'enabled')
  assert.equal(PILOT_RELEASE_MANIFEST.entry.concurrentCurrentOrganisations, 1)
  assert.equal(PILOT_RELEASE_MANIFEST.capabilities.caseBriefGeneration, 'disabled')
  assert.equal(PILOT_RELEASE_MANIFEST.capabilities.generatedAnswers, 'disabled')
  assert.equal(PILOT_RELEASE_MANIFEST.capabilities.agents, 'disabled')
  assert.ok(PILOT_RELEASE_MANIFEST.routes.developmentOnly.includes('/usage'))
  assert.ok(PILOT_RELEASE_MANIFEST.routes.releaseCriticalWorkspace.includes('/review'))
  assert.ok(PILOT_RELEASE_MANIFEST.routes.releaseCriticalWorkspace.includes('/team'))
  assert.ok(PILOT_RELEASE_MANIFEST.routes.releaseCriticalWorkspace.includes('/trash'))
  assert.ok(PILOT_RELEASE_MANIFEST.routes.compatibilityWorkspace.includes('/dashboard'))
})

test('the manifest fixes the September 14 release window and mandatory journey', () => {
  assert.deepEqual(PILOT_RELEASE_MANIFEST.releaseWindow, {
    targetStart: '2026-10-12',
    targetEnd: '2026-10-15',
    finalTarget: '2026-10-20',
    confidentialDataAcceptanceRequired: true,
  })
  assert.deepEqual(PILOT_RELEASE_MANIFEST.mandatoryJourney, [
    'signup',
    'verify_email',
    'create_or_join_organisation',
    'create_client_and_matter',
    'upload_pdf',
    'truthful_processing_or_manual_recovery',
    'resolve_applicable_typed_review',
    'assign_or_place_document',
    'reopen_exact_source_in_workbench',
    'inspect_document_in_matter_workspace',
  ])
  assert.deepEqual(PILOT_RELEASE_MANIFEST.uploadOrigins, {
    globalIntake: 'required_canonical_queue_and_processing_lifecycle',
    matter: 'required_retains_intended_matter_and_uses_canonical_queue_and_processing_lifecycle',
  })
})

test('conditional scope has its required cut order while retention remains enabled', () => {
  assert.deepEqual(conditionalPilotCapabilities(), [
    'relationshipSuggestions',
    'governedRelationshipEditing',
    'tasksAndReminders',
    'limitedFinancials',
    'matterScopedCitedRetrieval',
  ])
  assert.equal(PILOT_RELEASE_MANIFEST.capabilities.automaticRetention, 'enabled')
  assert.equal(PILOT_RELEASE_MANIFEST.capabilities.permanentPurge, 'enabled')
  assert.deepEqual(PILOT_RELEASE_MANIFEST.workers.releaseGated, [
    'dispatch-trash-permanent-delete',
    'sweep-trash-permanent-delete-daily',
  ])
  assert.ok(!PILOT_RELEASE_MANIFEST.workers.releaseGated.includes('reconcile-trash-permanent-delete'))
  assert.ok(!PILOT_RELEASE_MANIFEST.workers.releaseGated.includes('project-trash-retention-team-attention'))
  assert.deepEqual(PILOT_RELEASE_MANIFEST.conditionalCapabilityCutOrder, [
    'matterScopedCitedRetrieval',
    'tasksAndReminders',
    'limitedFinancials',
    'governedRelationshipEditing',
    'relationshipSuggestions',
  ])
  assert.deepEqual(PILOT_RELEASE_MANIFEST.explicitDeferrals, [
    'dashboard_and_today',
    'complete_tasks_and_my_work',
    'notification_digests_and_nonessential_channels',
    'full_notes_migration',
    'case_brief',
    'organisation_wide_semantic_search',
    'advanced_administration',
    'broad_realtime',
    'bulk_and_non_pdf_ingestion',
    'marketing_and_demo_refinement',
    'broad_financial_functionality',
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
  assert.equal(PILOT_RELEASE_MANIFEST.dataPolicy.localAndPreproduction, 'synthetic_or_sanitised_only')
  assert.equal(
    PILOT_RELEASE_MANIFEST.dataPolicy.production,
    'authorised_design_partner_confidential_documents_only_after_go_live',
  )
})

test('deployment identity is supplied by named environment inputs, not committed values', () => {
  assert.deepEqual(PILOT_RELEASE_MANIFEST.requiredDeploymentIdentity, {
    environmentVariable: 'CASECHAIN_RELEASE_ENVIRONMENT',
    organisationVariable: 'CASECHAIN_PILOT_ORGANISATION_ID',
    revisionVariable: 'CASECHAIN_RELEASE_REVISION',
  })
})
