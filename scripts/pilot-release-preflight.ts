import { PILOT_RELEASE_MANIFEST } from '../src/lib/pilot-release-manifest'
import { evaluatePilotReleasePreflight } from '../src/lib/pilot-release-preflight'

const localOnly = process.argv.includes('--local')
const { environmentVariable, organisationVariable, revisionVariable } = PILOT_RELEASE_MANIFEST.requiredDeploymentIdentity
const result = evaluatePilotReleasePreflight(PILOT_RELEASE_MANIFEST, {
  environment: process.env[environmentVariable],
  organisationId: process.env[organisationVariable],
  revision: process.env[revisionVariable],
})

// This report intentionally contains only policy states and named gates. It
// never loads or prints credentials, identity values, or confidential data.
console.log(
  JSON.stringify(
    {
      mode: localOnly ? 'release_matrix' : 'release',
      scope: 'repository release policy only; not application journey acceptance',
      ...result,
    },
    null,
    2,
  ),
)

if (!result.releaseMatrixReady || (!localOnly && !result.confidentialProductionReady)) {
  process.exitCode = 1
}
