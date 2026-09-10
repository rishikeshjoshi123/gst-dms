import { spawnSync } from 'node:child_process'

function run(command, args) {
  const result = spawnSync(command, args, { cwd: process.cwd(), stdio: 'inherit' })
  if (result.error) throw result.error
  if (result.status !== 0) process.exit(result.status ?? 1)
}

run('/bin/sh', ['scripts/acceptance/local-fixtures.sh'])
run(process.execPath, ['node_modules/@playwright/test/cli.js', 'test', 'tests/acceptance/matter-workbench.spec.ts'])
