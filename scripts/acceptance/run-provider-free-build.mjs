#!/usr/bin/env node

import { cpSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'

const repository = process.cwd()
const root = mkdtempSync(join(tmpdir(), 'casechain-provider-free-build-'))
const application = join(root, 'application')
const node = requireNode24()

const excluded = new Set(['.git', '.next', 'node_modules', 'test-results', 'playwright-report'])
const providerFreeEnvironment = { ...process.env }
for (const name of [
  'NEXT_PUBLIC_APP_URL', 'NEXT_PUBLIC_SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_ANON_KEY', 'SUPABASE_URL',
  'SUPABASE_ACCESS_TOKEN', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_PROJECT_REF',
  'TRIGGER_SECRET_KEY', 'TRIGGER_API_URL', 'RESEND_API_KEY', 'RESEND_FROM_EMAIL', 'CASECHAIN_EMAIL_CAPTURE_URL',
  'GOOGLE_APPLICATION_CREDENTIALS', 'GOOGLE_APPLICATION_CREDENTIALS_JSON',
  'GOOGLE_API_ENDPOINT', 'GOOGLE_CLOUD_PROJECT', 'GOOGLE_CLOUD_REGION', 'DOCUMENT_AI_LOCATION',
  'DOCUMENT_AI_OCR_PROCESSOR_ID', 'DOCUMENT_AI_OCR_PROCESSOR_VERSION', 'VERTEX_AI_API_KEY',
  'OPENAI_API_KEY', 'CASECHAIN_RELEASE_ENVIRONMENT', 'CASECHAIN_PILOT_ORGANISATION_ID',
  'CASECHAIN_RELEASE_REVISION',
]) delete providerFreeEnvironment[name]

try {
  cpSync(repository, application, {
    recursive: true,
    filter: source => !excluded.has(source.slice(source.lastIndexOf('/') + 1)) && !source.endsWith('/.env') && !source.includes('/.env.'),
  })
  symlinkSync(join(repository, 'node_modules'), join(application, 'node_modules'), 'dir')
  const fontMock = join(application, 'font-mock.cjs')
  writeFileSync(fontMock, `module.exports = new Proxy({}, { get(_target, url) { const mono = String(url).includes('Geist+Mono'); const family = mono ? 'Geist Mono' : 'Geist'; const file = ${JSON.stringify(join(repository, 'node_modules/next/dist/next-devtools/server/font/'))} + (mono ? 'geist-mono-latin.woff2' : 'geist-latin.woff2'); return "/* latin */\\n@font-face { font-family: '" + family + "'; font-style: normal; font-weight: 100 900; src: url(" + file + ") format('woff2'); }"; } });`)
  providerFreeEnvironment.NEXT_FONT_GOOGLE_MOCKED_RESPONSES = fontMock
  const result = spawnSync(node, ['node_modules/next/dist/bin/next', 'build', '--webpack'], {
    cwd: application,
    env: providerFreeEnvironment,
    stdio: 'inherit',
  })
  if (result.error) throw result.error
  process.exitCode = typeof result.status === 'number' ? result.status : 1
} finally {
  rmSync(root, { recursive: true, force: true })
}
