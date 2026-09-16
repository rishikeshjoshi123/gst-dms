#!/usr/bin/env node

import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { join, relative } from 'node:path'
import { requireNode24 } from './runtime.mjs'

export function fingerprintLintReports(reports, cwd = process.cwd()) {
  const diagnostics = reports.flatMap(report => report.messages.map(message => [
    relative(cwd, report.filePath),
    message.line ?? 0,
    message.column ?? 0,
    message.endLine ?? 0,
    message.endColumn ?? 0,
    message.ruleId ?? '',
    message.severity,
    message.message,
  ].join('|'))).sort()
  return {
    diagnosticCount: diagnostics.length,
    sha256: createHash('sha256').update(diagnostics.join('\n')).digest('hex'),
  }
}

export function checkFullLintBaseline({ execute = spawnSync, cwd = process.cwd(), output = process } = {}) {
  const node = requireNode24()
  const expected = JSON.parse(readFileSync(join(cwd, 'scripts/acceptance/release-candidate-lint-baseline.json'), 'utf8'))
  const result = execute(node, [join(cwd, 'node_modules/eslint/bin/eslint.js'), '--format', 'json'], {
    cwd,
    encoding: 'utf8',
    env: process.env,
  })
  if (result.error) throw result.error
  if (result.stderr) output.stderr.write(result.stderr)
  if (result.status !== 0 && result.status !== 1) {
    throw new Error(`Full lint exited unexpectedly with status ${result.status ?? 'unknown'}.`)
  }
  let actual
  try {
    actual = fingerprintLintReports(JSON.parse(result.stdout), cwd)
  } catch (error) {
    throw new Error(`Full lint did not return parseable JSON: ${error.message}`)
  }
  if (actual.diagnosticCount !== expected.diagnosticCount || actual.sha256 !== expected.sha256) {
    throw new Error(`Full lint baseline changed: expected ${expected.diagnosticCount}/${expected.sha256}, received ${actual.diagnosticCount}/${actual.sha256}.`)
  }
  output.stdout.write(`Full lint baseline matched: ${actual.diagnosticCount} diagnostics (${actual.sha256}).\n`)
}

if (process.argv[1] && new URL(import.meta.url).pathname === process.argv[1]) {
  try {
    checkFullLintBaseline()
  } catch (error) {
    console.error(`release-candidate full lint failed: ${error.message}`)
    process.exitCode = 1
  }
}
