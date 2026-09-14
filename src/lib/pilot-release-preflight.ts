import { PILOT_RELEASE_MANIFEST, type ExternalGateState } from './pilot-release-manifest'

type ReleaseManifest = typeof PILOT_RELEASE_MANIFEST
type DeploymentGates = ReleaseManifest['confidentialDeploymentGates']

export type DeploymentIdentityInput = {
  environment?: string
  organisationId?: string
  revision?: string
}

export type PilotReleasePreflight = {
  releaseMatrixReady: boolean
  confidentialProductionReady: boolean
  releaseMatrixFailures: string[]
  confidentialProductionBlockers: string[]
}

function isVerified(gate: ExternalGateState) {
  return gate === 'verified'
}

/** Evaluates repository policy only; it never reads secrets or contacts services. */
export function evaluatePilotReleasePreflight(
  manifest: ReleaseManifest = PILOT_RELEASE_MANIFEST,
  identity: DeploymentIdentityInput = {},
): PilotReleasePreflight {
  const releaseMatrixFailures: string[] = []

  if (manifest.schemaVersion < 2) releaseMatrixFailures.push('manifest schema must include first-release scope')
  if (manifest.releaseWindow.targetStart !== '2026-10-12' || manifest.releaseWindow.targetEnd !== '2026-10-15') {
    releaseMatrixFailures.push('October 12–15 target window is missing')
  }
  if (manifest.releaseWindow.finalTarget !== '2026-10-20') releaseMatrixFailures.push('October 20 final target is missing')
  if (!manifest.mandatoryJourney.includes('upload_pdf')) releaseMatrixFailures.push('mandatory journey is missing PDF upload')
  if (!manifest.uploadOrigins.globalIntake || !manifest.uploadOrigins.matter) {
    releaseMatrixFailures.push('both canonical upload origins are required')
  }
  if (manifest.capabilities.relationshipSuggestions !== 'conditional') {
    releaseMatrixFailures.push('relationship suggestions must remain conditional')
  }
  if (manifest.conditionalCapabilityCutOrder.at(-1) !== 'relationshipSuggestions') {
    releaseMatrixFailures.push('relationship suggestions must be cut last among optional capabilities')
  }
  if (!manifest.explicitDeferrals.includes('case_brief')) releaseMatrixFailures.push('Case Brief deferral is missing')
  if (manifest.limits.maximumFileBytes !== 25 * 1024 * 1024) releaseMatrixFailures.push('25 MiB PDF limit is missing')
  if (manifest.limits.pilotOrganisationUniqueAssetBytes !== 350 * 1024 * 1024) {
    releaseMatrixFailures.push('350 MiB pilot organisation limit is missing')
  }
  if (manifest.dataPolicy.localAndPreproduction !== 'synthetic_or_sanitised_only') {
    releaseMatrixFailures.push('local and pre-production data policy is unsafe')
  }

  const gates: DeploymentGates = manifest.confidentialDeploymentGates
  const confidentialProductionBlockers: string[] = []
  if (!isVerified(gates.exactRevisionAndEnvironmentIdentity)) {
    confidentialProductionBlockers.push('exact revision and environment identity is not verified')
  } else {
    if (identity.environment !== 'production' && identity.environment !== 'preproduction') {
      confidentialProductionBlockers.push('release environment identity is absent or invalid')
    }
    if (!identity.organisationId || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(identity.organisationId)) {
      confidentialProductionBlockers.push('pilot organisation identity is absent or invalid')
    }
    if (!identity.revision || !/^[0-9a-f]{40}$/i.test(identity.revision)) {
      confidentialProductionBlockers.push('release revision identity is absent or invalid')
    }
  }
  for (const [responsibility, owner] of Object.entries(gates.ownership)) {
    if (!owner) confidentialProductionBlockers.push(`${responsibility} ownership is unassigned`)
  }
  if (!isVerified(gates.compliantHost)) confidentialProductionBlockers.push('compliant production host is not verified')
  if (!isVerified(gates.databaseAndPrivateStorageRecovery)) {
    confidentialProductionBlockers.push('database and private Storage recovery drill is not verified')
  }
  if (!isVerified(gates.providerAndDeployedAcceptance)) {
    confidentialProductionBlockers.push('provider and deployed acceptance is not verified')
  }

  return {
    releaseMatrixReady: releaseMatrixFailures.length === 0,
    confidentialProductionReady: releaseMatrixFailures.length === 0 && confidentialProductionBlockers.length === 0,
    releaseMatrixFailures,
    confidentialProductionBlockers,
  }
}
