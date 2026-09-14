/**
 * Repository-owned release policy. This describes the approved pilot boundary
 * and local readiness inputs; it is never browser-side release authorization.
 */
export type PilotCapabilityState = 'enabled' | 'disabled' | 'conditional'
export type ExternalGateState = 'not_verified' | 'verified'

export const PILOT_RELEASE_MANIFEST = {
  schemaVersion: 2,
  audience: 'single_trusted_design_partner_organisation',
  releaseWindow: {
    targetStart: '2026-10-12',
    targetEnd: '2026-10-15',
    finalTarget: '2026-10-20',
    confidentialDataAcceptanceRequired: true,
  },
  routes: {
    public: ['/', '/contact', '/login', '/signup', '/auth/callback', '/api/invites/accept'],
    releaseCriticalWorkspace: [
      '/clients',
      '/matters',
      '/documents',
      '/inbox',
      '/review',
      '/settings',
      '/team',
      '/trash',
    ],
    // Existing stable routes may remain accessible without becoming October
    // release-critical capabilities or authorising their deferred breadth.
    compatibilityWorkspace: [
      '/dashboard',
      '/notes',
      '/notifications',
      '/tasks',
    ],
    developmentOnly: ['/dev/*', '/usage'],
  },
  roles: {
    owner: 'tenant administration and operational work',
    admin: 'delegated tenant administration and operational work',
    associate: 'operational work without tenant administration',
    viewer: 'read-only workspace access',
  },
  entry: {
    signup: 'email_verification_then_create_or_join',
    publicOrganisationCreation: 'enabled' as PilotCapabilityState,
    concurrentCurrentOrganisations: 1,
    invitationAcceptance: 'explicit_and_bound_to_verified_account',
  },
  mandatoryJourney: [
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
  ],
  uploadOrigins: {
    globalIntake: 'required_canonical_queue_and_processing_lifecycle',
    matter: 'required_retains_intended_matter_and_uses_canonical_queue_and_processing_lifecycle',
  },
  capabilities: {
    pdfDocumentWorkflow: 'enabled' as PilotCapabilityState,
    sourceGroundedExtractionWithReviewByException: 'enabled' as PilotCapabilityState,
    truthfulManualRecovery: 'enabled' as PilotCapabilityState,
    chronology: 'enabled' as PilotCapabilityState,
    readOnlyGraph: 'enabled' as PilotCapabilityState,
    manuallyVerifiedLegalDeadlines: 'enabled' as PilotCapabilityState,
    relationshipSuggestions: 'conditional' as PilotCapabilityState,
    governedRelationshipEditing: 'conditional' as PilotCapabilityState,
    tasksAndReminders: 'conditional' as PilotCapabilityState,
    limitedFinancials: 'conditional' as PilotCapabilityState,
    matterScopedCitedRetrieval: 'conditional' as PilotCapabilityState,
    caseBriefGeneration: 'disabled' as PilotCapabilityState,
    generatedAnswers: 'disabled' as PilotCapabilityState,
    agents: 'disabled' as PilotCapabilityState,
    automaticRetention: 'enabled' as PilotCapabilityState,
    permanentPurge: 'enabled' as PilotCapabilityState,
  },
  conditionalCapabilityCutOrder: [
    'matterScopedCitedRetrieval',
    'tasksAndReminders',
    'limitedFinancials',
    'governedRelationshipEditing',
    'relationshipSuggestions',
  ],
  explicitDeferrals: [
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
  ],
  workers: {
    enabled: [
      'document-lifecycle-event',
      'dispatch-document-outbox',
      'recover-document-outbox',
      'process-document',
      'reconcile-document-lifecycle-work',
      'clean-terminal-document-assets',
    ],
    disabled: ['generate-matter-wiki', 'deadline-reminders'],
    releaseGated: [
      'dispatch-trash-permanent-delete',
      'reconcile-trash-permanent-delete',
    ],
  },
  limits: {
    acceptedMimeTypes: ['application/pdf'],
    maximumFileBytes: 25 * 1024 * 1024,
    pilotOrganisationUniqueAssetBytes: 350 * 1024 * 1024,
  },
  dataPolicy: {
    localAndPreproduction: 'synthetic_or_sanitised_only',
    production: 'authorised_design_partner_confidential_documents_only_after_go_live',
    evaluationCorpus: 'authorised_local_input_not_committed_or_logged',
  },
  requiredDeploymentIdentity: {
    environmentVariable: 'CASECHAIN_RELEASE_ENVIRONMENT',
    organisationVariable: 'CASECHAIN_PILOT_ORGANISATION_ID',
    revisionVariable: 'CASECHAIN_RELEASE_REVISION',
  },
  confidentialDeploymentGates: {
    exactRevisionAndEnvironmentIdentity: 'not_verified' as ExternalGateState,
    ownership: {
      goLive: null as string | null,
      rollback: null as string | null,
      support: null as string | null,
      incident: null as string | null,
    },
    compliantHost: 'not_verified' as ExternalGateState,
    databaseAndPrivateStorageRecovery: 'not_verified' as ExternalGateState,
    providerAndDeployedAcceptance: 'not_verified' as ExternalGateState,
  },
} as const

export function conditionalPilotCapabilities() {
  return Object.entries(PILOT_RELEASE_MANIFEST.capabilities)
    .filter(([, state]) => state === 'conditional')
    .map(([capability]) => capability)
}
