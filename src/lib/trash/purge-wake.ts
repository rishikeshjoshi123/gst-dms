import { after } from 'next/server'
import { tasks } from '@trigger.dev/sdk/v3'

const options = { debounce: { key: 'trash-purge-dispatch', delay: '2s', maxDelay: '15s' } } as const
export const trashPurgeDispatcherTaskId = 'dispatch-trash-permanent-delete'

type TrashPurgeWakeTrigger = () => Promise<unknown>
type AfterScheduler = (callback: () => void | Promise<void>) => void

const triggerTrashPurgeDispatcher: TrashPurgeWakeTrigger = () => (
  tasks.trigger(trashPurgeDispatcherTaskId, undefined, options)
)

export function scheduleTrashPurgeWake(
  schedule: AfterScheduler = after,
  trigger: TrashPurgeWakeTrigger = triggerTrashPurgeDispatcher,
) {
  schedule(async () => {
    try {
      await trigger()
    } catch {
      console.warn('Trash purge wake was not accepted; scheduled recovery will resume durable work.')
    }
  })
}
