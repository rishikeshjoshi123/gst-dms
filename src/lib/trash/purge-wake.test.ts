import assert from 'node:assert/strict'
import test from 'node:test'

import { scheduleTrashPurgeWake, trashPurgeDispatcherTaskId } from './purge-wake'

test('schedules only the fixed content-free Trash purge dispatcher wake', async () => {
  let callback: (() => void | Promise<void>) | undefined
  let triggerCount = 0

  scheduleTrashPurgeWake(
    scheduled => { callback = scheduled },
    async () => { triggerCount += 1 },
  )

  assert.equal(trashPurgeDispatcherTaskId, 'dispatch-trash-permanent-delete')
  assert.equal(triggerCount, 0)
  await callback?.()
  assert.equal(triggerCount, 1)
})

test('a rejected Trash purge wake remains non-fatal', async () => {
  let callback: (() => void | Promise<void>) | undefined
  const originalWarn = console.warn
  const warnings: string[] = []
  console.warn = message => warnings.push(String(message))

  try {
    scheduleTrashPurgeWake(
      scheduled => { callback = scheduled },
      async () => { throw new Error('gateway unavailable') },
    )
    await callback?.()
  } finally {
    console.warn = originalWarn
  }

  assert.deepEqual(warnings, [
    'Trash purge wake was not accepted; scheduled recovery will resume durable work.',
  ])
})
