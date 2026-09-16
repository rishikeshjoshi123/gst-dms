import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { assertProviderFreeLocalEnvironment, runReleaseCandidate } from './run-release-candidate.mjs'

function output() {
  const messages = { stdout: [], stderr: [] }
  return {
    messages,
    stream: {
      stdout: { write: value => messages.stdout.push(value) },
      stderr: { write: value => messages.stderr.push(value) },
    },
  }
}

test('runs deterministic named stages in order and reports each exit', () => {
  const calls = []
  const captured = output()
  const stages = [
    { name: 'first', command: 'first-command', args: ['--one'] },
    { name: 'second', command: 'second-command', args: ['--two'] },
  ]
  const status = runReleaseCandidate({
    stages,
    environment: {},
    output: captured.stream,
    requireRuntime: () => {},
    execute: (command, args) => { calls.push([command, args]); return { status: 0 } },
  })

  assert.equal(status, 0)
  assert.deepEqual(calls, [['first-command', ['--one']], ['second-command', ['--two']]])
  assert.match(captured.messages.stdout.join(''), /first \(exit 0\)[\s\S]*second \(exit 0\)/)
})

test('stops at the first failing child and preserves its exit status', () => {
  const calls = []
  const captured = output()
  const status = runReleaseCandidate({
    stages: [
      { name: 'passes', command: 'pass', args: [] },
      { name: 'fails', command: 'fail', args: [] },
      { name: 'unrun', command: 'unrun', args: [] },
    ],
    environment: {},
    output: captured.stream,
    requireRuntime: () => {},
    execute: command => { calls.push(command); return { status: command === 'fail' ? 37 : 0 } },
  })

  assert.equal(status, 37)
  assert.deepEqual(calls, ['pass', 'fail'])
  assert.match(captured.messages.stderr.join(''), /stage fails: exit 37/)
})

test('refuses provider credentials, release identity, and non-loopback targets before any child starts', () => {
  assert.throws(() => assertProviderFreeLocalEnvironment({ RESEND_API_KEY: 'secret' }), /RESEND_API_KEY must be unset/)
  assert.throws(() => assertProviderFreeLocalEnvironment({ CASECHAIN_RELEASE_REVISION: 'a'.repeat(40) }), /CASECHAIN_RELEASE_REVISION must be unset/)
  assert.throws(() => assertProviderFreeLocalEnvironment({ SUPABASE_URL: 'https://example.supabase.co' }), /SUPABASE_URL must be unset or point to loopback/)
  assert.throws(() => assertProviderFreeLocalEnvironment({ NEXT_PUBLIC_APP_URL: 'https://release.example' }), /NEXT_PUBLIC_APP_URL must be unset or point to loopback/)
  assert.throws(() => assertProviderFreeLocalEnvironment({ CASECHAIN_EMAIL_CAPTURE_URL: 'https://mail.example' }), /CASECHAIN_EMAIL_CAPTURE_URL must be unset or point to loopback/)
  assert.throws(() => assertProviderFreeLocalEnvironment({ SUPABASE_PROJECT_REF: 'remote-project' }), /SUPABASE_PROJECT_REF must be unset/)
  assert.doesNotThrow(() => assertProviderFreeLocalEnvironment({ SUPABASE_URL: 'http://127.0.0.1:54321' }))
})

test('CLI prints a concise fail-closed configuration error', () => {
  const result = spawnSync(process.execPath, [new URL('./run-release-candidate.mjs', import.meta.url).pathname, '--dry-run'], {
    cwd: process.cwd(), encoding: 'utf8', env: { ...process.env, RESEND_API_KEY: 'blocked' },
  })
  assert.equal(result.status, 1)
  assert.match(result.stderr, /RESEND_API_KEY must be unset/)
  assert.doesNotMatch(result.stderr, /at assertProviderFreeLocalEnvironment/)
})

test('production build runs from a temporary copy without dotenv or provider inputs', () => {
  const source = readFileSync(new URL('./run-provider-free-build.mjs', import.meta.url), 'utf8')
  assert.match(source, /mkdtempSync/)
  assert.match(source, /source\.endsWith\('\/.env'\)/)
  assert.match(source, /source\.includes\('\/.env\.'\)/)
  assert.match(source, /delete providerFreeEnvironment\[name\]/)
  assert.match(source, /'build', '--webpack'/)
  assert.match(source, /NEXT_FONT_GOOGLE_MOCKED_RESPONSES/)
  for (const name of ['NEXT_PUBLIC_APP_URL', 'CASECHAIN_EMAIL_CAPTURE_URL', 'SUPABASE_PROJECT_REF', 'GOOGLE_API_ENDPOINT', 'GOOGLE_CLOUD_REGION', 'DOCUMENT_AI_LOCATION', 'DOCUMENT_AI_OCR_PROCESSOR_ID', 'DOCUMENT_AI_OCR_PROCESSOR_VERSION']) assert.match(source, new RegExp(`'${name}'`))
  assert.match(source, /rmSync\(root, \{ recursive: true, force: true \}\)/)
})

test('stateful journey blanks inherited captured-mail and API-secret configuration', () => {
  const source = readFileSync(new URL('./start-release-journey-server.mjs', import.meta.url), 'utf8')
  assert.match(source, /CASECHAIN_EMAIL_CAPTURE_URL: ''/)
  assert.match(source, /API_SECRET_KEY: ''/)
})
