import { after } from 'next/server'

const options = { debounce: { key: 'trash-purge-dispatch', delay: '2s', maxDelay: '15s' } } as const

export function scheduleTrashPurgeWake(schedule: typeof after = after) {
  schedule(async () => {
    try {
      const { trashPurgeDispatcher } = await import('@/trigger/outbox')
      await trashPurgeDispatcher.trigger(undefined, options)
    } catch {
      console.warn('Trash purge wake was not accepted; scheduled recovery will resume durable work.')
    }
  })
}
