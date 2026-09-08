import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const nextConfig = readFileSync(path.join(repositoryRoot, 'next.config.ts'), 'utf8')
const uploadAction = readFileSync(path.join(repositoryRoot, 'src/lib/actions/document.ts'), 'utf8')
const uploadClient = readFileSync(path.join(repositoryRoot, 'src/lib/uploads/resumable-document-upload.ts'), 'utf8')

test('PDF bytes bypass proxy and Server Action request buffers', () => {
  assert.doesNotMatch(nextConfig, /proxyClientMaxBodySize|bodySizeLimit/)
  assert.doesNotMatch(uploadAction, /FormData|\bas File\b|\.upload\(/)
  assert.match(uploadClient, /new tus\.Upload\(file/)
})
