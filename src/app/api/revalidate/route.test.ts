import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { POST } from './route'

const source = readFileSync(new URL('./route.ts', import.meta.url), 'utf8')

function request(body: unknown) {
  return new Request('http://localhost:3000/api/revalidate', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })
}

test('revalidation rejects missing configuration and malformed or mismatched body secrets', async () => {
  const original = process.env.API_SECRET_KEY
  try {
    for (const configured of [undefined, '', '   ']) {
      if (configured === undefined) delete process.env.API_SECRET_KEY
      else process.env.API_SECRET_KEY = configured
      const response = await POST(request({ paths: ['/dashboard'], secret: configured }))
      assert.equal(response.status, 401)
      assert.deepEqual(await response.json(), { message: 'Invalid token' })
    }
    process.env.API_SECRET_KEY = 'local-test-secret'
    for (const secret of [undefined, null, 17, '', 'wrong-secret']) {
      const response = await POST(request({ paths: ['/dashboard'], secret }))
      assert.equal(response.status, 401)
      assert.deepEqual(await response.json(), { message: 'Invalid token' })
    }
  } finally {
    if (original === undefined) delete process.env.API_SECRET_KEY
    else process.env.API_SECRET_KEY = original
  }
})

test('secret validation precedes every revalidatePath call', () => {
  const guard = source.indexOf("typeof configuredSecret !== 'string'")
  const revalidation = source.indexOf('revalidatePath(path)')
  assert.ok(guard >= 0 && revalidation > guard)
})
