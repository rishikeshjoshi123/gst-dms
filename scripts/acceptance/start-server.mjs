import { spawn, spawnSync } from 'node:child_process'

const status = spawnSync('./node_modules/.bin/supabase', ['status', '-o', 'env'], {
  cwd: process.cwd(),
  encoding: 'utf8',
})

if (status.status !== 0) {
  process.stderr.write(status.stderr)
  process.exit(status.status ?? 1)
}

const local = Object.fromEntries(status.stdout.trim().split('\n').map((line) => {
  const separator = line.indexOf('=')
  const key = line.slice(0, separator)
  const value = line.slice(separator + 1).replace(/^"|"$/g, '')
  return [key, value]
}))

for (const key of ['API_URL', 'DB_URL', 'INBUCKET_URL', 'STORAGE_S3_URL', 'ANON_KEY', 'SERVICE_ROLE_KEY']) {
  if (!local[key]) throw new Error(`Local Supabase did not report ${key}.`)
}

const api = new URL(local.API_URL)
const database = new URL(local.DB_URL)
const capturedMail = new URL(local.INBUCKET_URL)
const storage = new URL(local.STORAGE_S3_URL)
if ([api, database, capturedMail, storage].some((url) => !['127.0.0.1', 'localhost'].includes(url.hostname))) {
  throw new Error('Refusing to start acceptance against a non-loopback database, Storage, or captured-mail target.')
}

const env = {
  ...process.env,
  NEXT_PUBLIC_APP_URL: 'http://127.0.0.1:3100',
  NEXT_PUBLIC_SUPABASE_URL: local.API_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: local.ANON_KEY,
  SUPABASE_SERVICE_ROLE_KEY: local.SERVICE_ROLE_KEY,
  TRIGGER_SECRET_KEY: '',
  TRIGGER_API_URL: 'http://127.0.0.1:9',
  // Resend validates constructor presence at module load. This local-only
  // sentinel is deliberately non-routable and never authorises a provider.
  RESEND_API_KEY: 're_acceptance_disabled',
  RESEND_FROM_EMAIL: 'acceptance@invalid.example',
  GOOGLE_APPLICATION_CREDENTIALS: '',
  GOOGLE_APPLICATION_CREDENTIALS_JSON: '',
  GOOGLE_CLOUD_PROJECT: '',
  DOCUMENT_AI_LOCATION: '',
  DOCUMENT_AI_OCR_PROCESSOR_ID: '',
  DOCUMENT_AI_OCR_PROCESSOR_VERSION: '',
}

const child = spawn('/opt/homebrew/bin/npm', ['run', 'dev', '--', '--hostname', '127.0.0.1', '--port', '3100'], {
  cwd: process.cwd(),
  env,
  stdio: 'inherit',
})

for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal))
child.on('exit', (code, signal) => {
  if (signal) process.kill(process.pid, signal)
  else process.exit(code ?? 1)
})
