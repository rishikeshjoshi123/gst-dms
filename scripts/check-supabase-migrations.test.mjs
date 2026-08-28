import assert from 'node:assert/strict'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'

import { checkMigrationDirectory } from './check-supabase-migrations.mjs'

function withMigrationFixture(files, run) {
  const directory = mkdtempSync(path.join(os.tmpdir(), 'casechain-migrations-'))

  try {
    for (const filename of files) {
      writeFileSync(path.join(directory, filename), '-- fixture\n')
    }
    run(directory)
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
}

test('accepts unique versions with monotonic gaps', () => {
  withMigrationFixture(['00001_initial.sql', '00003_follow_up.sql'], (directory) => {
    assert.deepEqual(
      checkMigrationDirectory(directory).map((migration) => migration.filename),
      ['00001_initial.sql', '00003_follow_up.sql'],
    )
  })
})

test('rejects duplicate numeric versions', () => {
  withMigrationFixture(['00001_initial.sql', '00001_conflict.sql'], (directory) => {
    assert.throws(() => checkMigrationDirectory(directory), /duplicate migration version 00001/)
  })
})

test('rejects malformed migration filenames', () => {
  withMigrationFixture(['00001_initial.sql', 'not-a-migration.sql'], (directory) => {
    assert.throws(() => checkMigrationDirectory(directory), /malformed migration filename/)
  })
})
