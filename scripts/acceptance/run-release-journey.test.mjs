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
 assert.match(source,/waitForCapturedMail\(local\)/)
 assert.match(source,/randomBytes\(6\)/)
 assert.match(source,/RELEASE_JOURNEY_OWNER_EMAIL: ownerEmail/)
})

test('profile ownership is exclusive before Docker inspection and is released only after cleanup',()=>{
 assert.match(source,/mkdirSync\(lockPath\)/)
 assert.match(source,/flag: 'wx'/)
 assert.match(source,/owner\.runId !== runId/)
 assert.ok(source.indexOf('acquireOwnershipLock()\n  const existing') < source.indexOf("await run('docker', ['ps', '-a'"))
 assert.match(source,/releaseOwnershipLock\(\)/)
 assert.match(source,/name\.startsWith\('supabase_'\) && name\.endsWith/)
})
