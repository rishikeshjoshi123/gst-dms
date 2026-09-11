import { realpathSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { sep } from 'node:path'
import { spawn, spawnSync } from 'node:child_process'
import { acceptanceProjectPath, nodeModuleLaunch, requireNode24 } from './runtime.mjs'

const nodeExec = requireNode24()
const workdir = process.env.ONBOARDING_SUPABASE_WORKDIR
if (!workdir) throw new Error('The isolated onboarding Supabase workdir is required.')
const resolvedWorkdir = realpathSync(workdir)
const resolvedTemp = realpathSync(tmpdir())
if (!resolvedWorkdir.startsWith(`${resolvedTemp}${sep}`)) {
  throw new Error('Refusing an onboarding Supabase workdir outside the temporary directory.')
}

const supabaseCli = acceptanceProjectPath('node_modules/supabase/dist/supabase.js')
const status = spawnSync(nodeExec, [supabaseCli, 'status', '-o', 'env'], {
  cwd: resolvedWorkdir,
  encoding: 'utf8',
})
if (status.status !== 0) throw new Error(status.stderr || 'Isolated Supabase status failed.')
const local = Object.fromEntries(status.stdout.trim().split('\n').map((line) => {
  const separator = line.indexOf('=')
  return [line.slice(0, separator), line.slice(separator + 1).replace(/^"|"$/g, '')]
}))
for (const key of ['API_URL', 'DB_URL', 'INBUCKET_URL', 'ANON_KEY', 'SERVICE_ROLE_KEY']) {
  if (!local[key]) throw new Error(`Isolated Supabase did not report ${key}.`)
}
for (const key of ['API_URL', 'DB_URL', 'INBUCKET_URL']) {
  if (!['127.0.0.1', 'localhost'].includes(new URL(local[key]).hostname)) {
    throw new Error(`Refusing non-loopback ${key}.`)
  }
}

const appUrl = process.env.ONBOARDING_APP_URL ?? 'http://127.0.0.1:3200'
if (!['127.0.0.1', 'localhost'].includes(new URL(appUrl).hostname)) {
  throw new Error('Refusing non-loopback onboarding application URL.')
}
const env = {
  ...process.env,
  NEXT_PUBLIC_APP_URL: appUrl,
  NEXT_PUBLIC_SUPABASE_URL: local.API_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: local.ANON_KEY,
  SUPABASE_SERVICE_ROLE_KEY: local.SERVICE_ROLE_KEY,
  TRIGGER_SECRET_KEY: '',
  TRIGGER_API_URL: 'http://127.0.0.1:9',
  RESEND_API_KEY: 're_acceptance_disabled',
  RESEND_FROM_EMAIL: 'acceptance@invalid.example',
  GOOGLE_APPLICATION_CREDENTIALS: '',
  GOOGLE_APPLICATION_CREDENTIALS_JSON: '',
  GOOGLE_CLOUD_PROJECT: '',
  DOCUMENT_AI_LOCATION: '',
  DOCUMENT_AI_OCR_PROCESSOR_ID: '',
  DOCUMENT_AI_OCR_PROCESSOR_VERSION: '',
}
const next = nodeModuleLaunch(
  acceptanceProjectPath('node_modules/next/dist/bin/next'),
  ['dev', '--hostname', '127.0.0.1', '--port', new URL(appUrl).port],
)
const child = spawn(next.command, next.args, { cwd: acceptanceProjectPath('.'), env, stdio: 'inherit' })
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal))
child.on('exit', (code, signal) => {
  if (signal) process.kill(process.pid, signal)
  else process.exit(code ?? 1)
})
