import { PILOT_RELEASE_MANIFEST } from './pilot-release-manifest'

export function isCaseBriefGenerationEnabled() {
  return PILOT_RELEASE_MANIFEST.capabilities.caseBriefGeneration === 'enabled'
}

export function isPublicOrganisationCreationEnabled() {
  return PILOT_RELEASE_MANIFEST.entry.publicOrganisationCreation === 'enabled'
}
