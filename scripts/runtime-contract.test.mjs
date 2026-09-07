import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8')
const packageJson = JSON.parse(read('package.json'))

test('repository and Trigger workers pin the approved Node 24 runtime', () => {
  assert.equal(read('.nvmrc').trim(), '24')
  assert.equal(packageJson.engines.node, '>=24 <25')
  assert.equal(packageJson.packageManager, 'npm@11.6.0')
  assert.match(packageJson.devDependencies['@types/node'], /^\^24/)
  assert.match(read('trigger.config.ts'), /runtime:\s*['"]node-24['"]/)

  for (const workflow of [
    '.github/workflows/supabase-migrations.yml',
    '.github/workflows/deploy-project-portal.yml',
  ]) {
    assert.doesNotMatch(read(workflow), /node-version:\s*(?:20|22)\b/)
    assert.match(read(workflow), /node-version:\s*24\b/)
  }
})

test('active application and worker code uses the current Trigger SDK export', () => {
  for (const source of [
    'trigger.config.ts',
    'src/lib/actions/wiki.ts',
    'src/lib/outbox/wake.ts',
    'src/lib/trash/purge-wake.ts',
    'src/trigger/jobs.ts',
    'src/trigger/outbox.ts',
  ]) {
    assert.doesNotMatch(read(source), /@trigger\.dev\/sdk\/v3/)
  }
})
