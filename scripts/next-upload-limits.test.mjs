import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const nextConfig = readFileSync(path.join(repositoryRoot, 'next.config.ts'), 'utf8')

test('keeps proxy and server-action buffers above 25 MiB PDFs but below the provider ceiling', () => {
  assert.match(nextConfig, /proxyClientMaxBodySize:\s*'27mb'/)
  assert.match(nextConfig, /serverActions:\s*\{\s*bodySizeLimit:\s*'27mb'/s)
})
