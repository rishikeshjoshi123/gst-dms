export type PilotCapabilityState = 'enabled' | 'disabled' | 'approval_required'

export const PILOT_RELEASE_MANIFEST = {
  schemaVersion: 1,
  audience: 'single_design_partner_organisation',
  routes: {
    public: ['/', '/contact', '/login', '/signup', '/auth/callback', '/api/invites/accept'],
    enabledWorkspace: [
      '/dashboard',
      '/clients',
      '/matters',
      '/documents',
      '/inbox',
      '/review',
      '/notes',
      '/notifications',
      '/settings',
      '/tasks',
      '/trash',
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
  },
  capabilities: {
    pdfDocumentWorkflow: 'enabled' as PilotCapabilityState,
    matterScopedCitedRetrieval: 'enabled' as PilotCapabilityState,
    caseBriefGeneration: 'disabled' as PilotCapabilityState,
    generatedAnswers: 'disabled' as PilotCapabilityState,
    agents: 'disabled' as PilotCapabilityState,
    automaticRetention: 'enabled' as PilotCapabilityState,
    permanentPurge: 'enabled' as PilotCapabilityState,
  },
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
    approvalRequired: [
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
    preproduction: 'synthetic_or_sanitised_only',
    production: 'authorised_design_partner_documents_only',
    evaluationCorpus: 'authorised_local_input_not_committed',
  },
  requiredDeploymentIdentity: {
    environmentVariable: 'CASECHAIN_RELEASE_ENVIRONMENT',
    organisationVariable: 'CASECHAIN_PILOT_ORGANISATION_ID',
    revisionVariable: 'CASECHAIN_RELEASE_REVISION',
  },
} as const

export function unresolvedPilotApprovals() {
  return Object.entries(PILOT_RELEASE_MANIFEST.capabilities)
    .filter(([, state]) => state === 'approval_required')
    .map(([capability]) => capability)
}
