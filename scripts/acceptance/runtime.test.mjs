import assert from 'node:assert/strict'
import test from 'node:test'

import { acceptanceProjectPath, nodeModuleLaunch, requireNode24 } from './runtime.mjs'

test('acceptance runtime accepts only Node 24', () => {
  assert.equal(
    requireNode24({ version: '24.8.0', execPath: '/runtime/node' }),
    '/runtime/node',
  )
  assert.throws(
    () => requireNode24({ version: '22.21.0', execPath: '/other/node' }),
    /requires Node 24 exactly; received 22\.21\.0 from \/other\/node/,
  )
  assert.throws(
    () => requireNode24({ version: 'invalid', execPath: '/other/node' }),
    /requires Node 24 exactly/,
  )
})

test('project modules launch with the validated Node executable', () => {
  const nextCli = acceptanceProjectPath('node_modules/next/dist/bin/next')
  const launch = nodeModuleLaunch(nextCli, ['dev'], {
    version: '24.8.0',
    execPath: '/runtime/node',
  })

  assert.equal(launch.command, '/runtime/node')
  assert.deepEqual(launch.args, [nextCli, 'dev'])
  assert.match(nextCli, /node_modules\/next\/dist\/bin\/next$/)
})
