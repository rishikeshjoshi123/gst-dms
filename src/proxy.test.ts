import assert from 'node:assert/strict'
import test from 'node:test'

import { NextRequest } from 'next/server'

import { proxy } from './proxy'

test('developer review routes do not require a Supabase session', async () => {
  for (const pathname of ['/dev', '/dev/design-system', '/dev/review-workspace-concept']) {
    const response = await proxy(new NextRequest(`http://localhost:3000${pathname}`))

    assert.equal(response.status, 200)
    assert.equal(response.headers.get('location'), null)
  }
})
