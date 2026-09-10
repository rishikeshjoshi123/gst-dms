import { spawnSync } from 'node:child_process'
import { acceptanceProjectPath, nodeModuleLaunch, requireNode24 } from './runtime.mjs'

const nodeExec = requireNode24()

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: process.cwd(),
    stdio: 'inherit',
    ...options,
  })
  if (result.error) throw result.error
  if (result.status !== 0) process.exit(result.status ?? 1)
}

run('/bin/sh', ['scripts/acceptance/local-fixtures.sh'], {
  env: { ...process.env, ACCEPTANCE_NODE_EXEC: nodeExec },
})

const playwright = nodeModuleLaunch(
  acceptanceProjectPath('node_modules/@playwright/test/cli.js'),
  ['test', 'tests/acceptance/matter-workbench.spec.ts'],
)
run(playwright.command, playwright.args)
