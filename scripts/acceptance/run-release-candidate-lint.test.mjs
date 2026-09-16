import assert from 'node:assert/strict'
import test from 'node:test'
import { fingerprintLintReports } from './run-release-candidate-lint.mjs'

test('full-lint fingerprint is deterministic regardless of ESLint report order', () => {
  const reports = [
    { filePath: '/repo/b.ts', messages: [{ line: 2, column: 3, endLine: 2, endColumn: 4, ruleId: 'rule-b', severity: 2, message: 'B' }] },
    { filePath: '/repo/a.ts', messages: [{ line: 1, column: 1, ruleId: 'rule-a', severity: 1, message: 'A' }] },
  ]
  const first = fingerprintLintReports(reports, '/repo')
  const second = fingerprintLintReports([...reports].reverse(), '/repo')
  assert.deepEqual(first, second)
  assert.equal(first.diagnosticCount, 2)
})
