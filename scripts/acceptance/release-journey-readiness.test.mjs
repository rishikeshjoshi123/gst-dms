import assert from 'node:assert/strict'
import test from 'node:test'
import { authHealthIsReady, capturedMailIsReady } from './release-journey-readiness.mjs'

test('Auth readiness requires HTTP 200 and a versioned health body', async () => {
  assert.equal(await authHealthIsReady(Response.json({ name: 'GoTrue', version: 'v1' })), true)
  assert.equal(await authHealthIsReady(Response.json({ version: 'v1' }, { status: 404 })), false)
  assert.equal(await authHealthIsReady(Response.json({ error: 'unavailable' })), false)
  assert.equal(await authHealthIsReady(new Response('not json', { status: 200 })), false)
})

test('Mailpit/Inbucket readiness requires HTTP 200 and a message-list body', async () => {
  assert.equal(await capturedMailIsReady(Response.json({ messages: [] })), true)
  assert.equal(await capturedMailIsReady(Response.json([])), true)
  assert.equal(await capturedMailIsReady(Response.json({ messages: [] }, { status: 404 })), false)
  assert.equal(await capturedMailIsReady(Response.json({ error: 'missing' })), false)
})
