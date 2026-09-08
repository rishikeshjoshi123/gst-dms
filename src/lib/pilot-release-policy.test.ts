import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { isCaseBriefGenerationEnabled } from './pilot-release-policy'

const wikiActions = readFileSync(new URL('./actions/wiki.ts', import.meta.url), 'utf8')
const triggerWikiGeneration = wikiActions.slice(
  wikiActions.indexOf('export async function triggerWikiGeneration'),
)
const workers = readFileSync(new URL('../trigger/jobs.ts', import.meta.url), 'utf8')
const wikiWorker = workers.slice(workers.indexOf("id: 'generate-matter-wiki'"))
const wikiConsumer = readFileSync(
  new URL('../components/matters/CaseWikiTab.tsx', import.meta.url),
  'utf8',
)

test('the pilot release disables Case Brief generation by default', () => {
  assert.equal(isCaseBriefGenerationEnabled(), false)
})

test('the server action denies generation before authentication or dispatch', () => {
  const policyCheck = triggerWikiGeneration.indexOf('isCaseBriefGenerationEnabled()')
  const clientCreation = triggerWikiGeneration.indexOf('createClient()')
  const dispatch = triggerWikiGeneration.indexOf("tasks.trigger('generate-matter-wiki'")

  assert.ok(policyCheck >= 0)
  assert.ok(clientCreation > policyCheck)
  assert.ok(dispatch > clientCreation)
  assert.match(triggerWikiGeneration, /Case Brief generation is not available in this release/)
})

test('the worker denies direct dispatch before service access or model generation', () => {
  const policyCheck = wikiWorker.indexOf('isCaseBriefGenerationEnabled()')
  const serviceClient = wikiWorker.indexOf("import('@/lib/supabase/server')")
  const model = wikiWorker.indexOf('generateWikiSummary(matterContext)')

  assert.ok(policyCheck >= 0)
  assert.ok(serviceClient > policyCheck)
  assert.ok(model > serviceClient)
  assert.match(wikiWorker, /disabled_by_release_policy/)
})

test('the live compatibility UI exposes no generation trigger', () => {
  assert.doesNotMatch(wikiConsumer, /triggerWikiGeneration|Generate Case Wiki|Regenerate Wiki/)
  assert.match(wikiConsumer, /Case Brief generation is not available in this release/)
})
