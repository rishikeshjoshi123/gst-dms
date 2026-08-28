#!/usr/bin/env node

import { readdirSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const migrationFilename = /^(\d+)_([a-z0-9]+(?:_[a-z0-9]+)*)\.sql$/
const scriptDirectory = path.dirname(fileURLToPath(import.meta.url))
const defaultMigrationDirectory = path.resolve(scriptDirectory, '../supabase/migrations')

export function checkMigrationDirectory(directory) {
  let entries

  try {
    entries = readdirSync(directory, { withFileTypes: true })
  } catch (error) {
    throw new Error(`Unable to read migration directory: ${error.code ?? 'unknown error'}`)
  }

  const migrations = []
  const problems = []

  for (const entry of entries) {
    if (!entry.isFile()) {
      if (!entry.isDirectory()) {
        problems.push(`unsupported migration directory entry: ${entry.name}`)
      }
      continue
    }

    const match = entry.name.match(migrationFilename)
    if (!match) {
      problems.push(`malformed migration filename: ${entry.name}`)
      continue
    }

    migrations.push({ filename: entry.name, version: match[1] })
  }

  migrations.sort((left, right) => {
    const versionOrder = BigInt(left.version) - BigInt(right.version)
    return versionOrder === 0n
      ? left.filename.localeCompare(right.filename)
      : versionOrder < 0n
        ? -1
        : 1
  })

  for (let index = 1; index < migrations.length; index += 1) {
    const previous = migrations[index - 1]
    const current = migrations[index]
    if (BigInt(previous.version) === BigInt(current.version)) {
      problems.push(
        `duplicate migration version ${current.version}: ${previous.filename}, ${current.filename}`,
      )
    }
  }

  if (problems.length > 0) {
    throw new Error(problems.join('\n'))
  }

  return migrations
}

function main() {
  const directory = process.argv[2]
    ? path.resolve(process.cwd(), process.argv[2])
    : defaultMigrationDirectory
  const displayDirectory = path.relative(process.cwd(), directory) || '.'

  try {
    const migrations = checkMigrationDirectory(directory)
    console.log(`Migration check passed: ${migrations.length} unique versions in ${displayDirectory}`)
  } catch (error) {
    console.error(`Migration check failed in ${displayDirectory}: ${error.message}`)
    process.exitCode = 1
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main()
}
