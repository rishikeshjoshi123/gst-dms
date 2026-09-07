import { renameSync, rmSync, writeFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import path from 'node:path'

import { refineSupabaseTypes } from './refine-supabase-types.mjs'

const outputPath = path.resolve(process.cwd(), 'src/lib/supabase/database.types.ts')
const useLocalDatabase = process.argv.includes('--local')
const projectRef = process.env.SUPABASE_PROJECT_REF

if (!useLocalDatabase && !projectRef) {
  throw new Error('Set SUPABASE_PROJECT_REF or run npm run db:types:local')
}

const argumentsList = ['gen', 'types', 'typescript']
if (useLocalDatabase) {
  argumentsList.push('--local')
} else {
  argumentsList.push('--project-id', projectRef)
}

const generated = spawnSync('supabase', argumentsList, {
  cwd: process.cwd(),
  encoding: 'utf8',
  maxBuffer: 20 * 1024 * 1024,
})

if (generated.error) {
  throw generated.error
}
if (generated.status !== 0) {
  process.stderr.write(generated.stderr)
  throw new Error(`Supabase type generation failed with exit code ${generated.status}`)
}

const temporaryPath = `${outputPath}.generated-${process.pid}`
try {
  writeFileSync(temporaryPath, refineSupabaseTypes(generated.stdout))
  renameSync(temporaryPath, outputPath)
} finally {
  rmSync(temporaryPath, { force: true })
}
