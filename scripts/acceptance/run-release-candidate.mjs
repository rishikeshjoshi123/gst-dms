#!/usr/bin/env node

import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { requireNode24 } from './runtime.mjs'

const LOOPBACK_HOSTS = new Set(['127.0.0.1', 'localhost', '::1'])
const REMOTE_URL_VARIABLES = [
  'NEXT_PUBLIC_SUPABASE_URL',
  'NEXT_PUBLIC_APP_URL',
  'SUPABASE_URL',
  'CASECHAIN_EMAIL_CAPTURE_URL',
  'TRIGGER_API_URL',
  'RESEND_API_URL',
  'GOOGLE_API_ENDPOINT',
]
const PROVIDER_CREDENTIAL_VARIABLES = [
  'SUPABASE_ACCESS_TOKEN',
  'SUPABASE_SERVICE_ROLE_KEY',
  'TRIGGER_SECRET_KEY',
  'RESEND_API_KEY',
  'GOOGLE_APPLICATION_CREDENTIALS',
  'GOOGLE_APPLICATION_CREDENTIALS_JSON',
  'GOOGLE_CLOUD_PROJECT',
  'VERTEX_AI_API_KEY',
  'OPENAI_API_KEY',
]
const RELEASE_IDENTITY_VARIABLES = [
  'CASECHAIN_RELEASE_ENVIRONMENT',
  'CASECHAIN_PILOT_ORGANISATION_ID',
  'CASECHAIN_RELEASE_REVISION',
]
const REMOTE_PROJECT_IDENTITY_VARIABLES = ['SUPABASE_PROJECT_REF']

export const RELEASE_CANDIDATE_STAGES = [
  { name: 'release-candidate-orchestrator-contracts', command: 'npm', args: ['run', 'test:release-candidate'] },
  { name: 'node-24-runtime-contract', command: 'npm', args: ['run', 'test:runtime-contract'] },
  { name: 'migration-uniqueness', command: 'npm', args: ['run', 'test:db:migrations'] },
  { name: 'refined-database-type-contract', command: 'npm', args: ['run', 'test:db:types'] },
  { name: 'pilot-release-policy-and-application-contracts', command: 'npm', args: ['run', 'test:pilot-release-preflight'] },
  {
    name: 'stateful-release-journey-runner-contracts',
    command: 'node',
    args: ['--test', 'scripts/acceptance/run-release-journey.test.mjs', 'scripts/acceptance/release-journey-readiness.test.mjs', 'scripts/acceptance/release-journey-boundary.test.mjs'],
  },
  { name: 'typescript', command: 'npm', args: ['run', 'typecheck'] },
  { name: 'full-lint-baseline', command: 'node', args: ['scripts/acceptance/run-release-candidate-lint.mjs'] },
  {
    name: 'scoped-lint',
    command: 'npm',
    args: ['run', 'lint', '--', 'scripts/acceptance/run-release-candidate.mjs', 'scripts/acceptance/run-release-candidate.test.mjs', 'scripts/acceptance/run-release-candidate-lint.mjs', 'scripts/acceptance/run-release-candidate-lint.test.mjs', 'scripts/acceptance/run-provider-free-build.mjs', 'scripts/acceptance/start-release-journey-server.mjs'],
  },
  { name: 'provider-free-production-build', command: 'node', args: ['scripts/acceptance/run-provider-free-build.mjs'] },
  { name: 'stateful-confirmation-required-synthetic-release-journey', command: 'npm', args: ['run', 'acceptance:release-journey'] },
]

function hasValue(value) {
  return typeof value === 'string' && value.trim().length > 0
}

function isLoopbackUrl(value) {
  try {
    return LOOPBACK_HOSTS.has(new URL(value).hostname)
  } catch {
    return false
  }
}

/** Reject inputs that could make an ostensibly local check reach a release or provider. */
export function assertProviderFreeLocalEnvironment(environment = process.env) {
  const problems = []

  for (const variable of REMOTE_URL_VARIABLES) {
    if (hasValue(environment[variable]) && !isLoopbackUrl(environment[variable])) {
      problems.push(`${variable} must be unset or point to loopback`)
    }
  }
  for (const variable of PROVIDER_CREDENTIAL_VARIABLES) {
    if (hasValue(environment[variable])) problems.push(`${variable} must be unset`)
  }
  for (const variable of RELEASE_IDENTITY_VARIABLES) {
    if (hasValue(environment[variable])) problems.push(`${variable} must be unset for a provider-free local rehearsal`)
  }
  for (const variable of REMOTE_PROJECT_IDENTITY_VARIABLES) {
    if (hasValue(environment[variable])) problems.push(`${variable} must be unset for a provider-free local rehearsal`)
  }
  if (environment.VERCEL_ENV === 'production' || environment.NODE_ENV === 'production' && environment.CI_RELEASE_TARGET === 'production') {
    problems.push('production release target configuration is not allowed')
  }

  if (problems.length > 0) {
    throw new Error(`Refusing release-candidate check:\n- ${problems.join('\n- ')}`)
  }
}

export function runReleaseCandidate({
  stages = RELEASE_CANDIDATE_STAGES,
  execute = spawnSync,
  environment = process.env,
  output = process,
  requireRuntime = requireNode24,
} = {}) {
  requireRuntime()
  assertProviderFreeLocalEnvironment(environment)

  for (const stage of stages) {
    output.stdout.write(`\n==> release-candidate stage: ${stage.name}\n`)
    const result = execute(stage.command, stage.args, { cwd: process.cwd(), env: environment, stdio: 'inherit' })
    if (result.error) {
      output.stderr.write(`release-candidate failed at stage ${stage.name}: could not start child (${result.error.message})\n`)
      return 1
    }
    const status = typeof result.status === 'number' ? result.status : 1
    if (status !== 0) {
      output.stderr.write(`release-candidate failed at stage ${stage.name}: exit ${status}\n`)
      return status
    }
    output.stdout.write(`<== release-candidate stage passed: ${stage.name} (exit 0)\n`)
  }

  output.stdout.write('\nrelease-candidate completed: all local, provider-free stages exited 0. This is not confidential-production readiness, provider validation, recovery evidence, or deployment approval.\n')
  return 0
}

function main() {
  if (process.argv.includes('--dry-run')) {
    requireNode24()
    assertProviderFreeLocalEnvironment()
    for (const stage of RELEASE_CANDIDATE_STAGES) console.log(`${stage.name}: ${stage.command} ${stage.args.join(' ')}`)
    return 0
  }
  return runReleaseCandidate()
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    process.exitCode = main()
  } catch (error) {
    console.error(error.message)
    process.exitCode = 1
  }
}
