import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source=readFileSync(new URL('./run-release-journey.mjs',import.meta.url),'utf8')

test('release journey interruption cleanup is single-entry and exact-project scoped',()=>{
 assert.match(source,/let cleanupStarted = false/)
 assert.match(source,/if \(cleanupStarted\) return/)
 assert.match(source,/activeChild\?\.kill\('SIGTERM'\)/)
 assert.match(source,/\[cli, 'stop', '--no-backup', '--workdir', root\]/)
 assert.match(source,/resolvedRoot\.startsWith\(`\$\{resolvedTemp\}\$\{sep\}`\)/)
 assert.match(source,/process\.once\(signal/)
 assert.doesNotMatch(source,/docker[^\n]+stop/)
})

test('runner waits for local Auth and captured mail and uses a per-run address',()=>{
 assert.match(source,/waitForLocalService\(`\$\{local\.API_URL\}\/auth\/v1\/health`/)
 assert.match(source,/waitForLocalService\(`\$\{local\.INBUCKET_URL\}\/api\/v1\/mailbox\/release-readiness@acceptance\.test`/)
 assert.match(source,/randomBytes\(6\)/)
 assert.match(source,/RELEASE_JOURNEY_OWNER_EMAIL: ownerEmail/)
})
