const DATE_KEY_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/
const MILLISECONDS_PER_DAY = 24 * 60 * 60 * 1000

export type DeadlineAttentionItem = {
  id: string
  dueDate: string
  type: 'appeal_window' | 'pre_deposit' | 'hearing_date' | 'reply_deadline' | 'stay_application' | 'other'
  description: string | null
  matter: {
    title: string
    clientName: string
  }
}

export type DeadlineAttentionPayload =
  | {
      status: 'available'
      asOfDate: string
      timeZone: string
      items: DeadlineAttentionItem[]
    }
  | {
      status: 'unavailable'
      asOfDate: null
      timeZone: null
      items: []
    }

export type DeadlineDayStatus = {
  kind: 'overdue' | 'today' | 'future'
  dayDelta: number
  label: string
}

function dateKeyToEpochDay(dateKey: string): number {
  const match = DATE_KEY_PATTERN.exec(dateKey)
  if (!match) throw new RangeError(`Invalid date key: ${dateKey}`)

  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
    throw new RangeError(`Invalid date key: ${dateKey}`)
  }

  const date = new Date(0)
  date.setUTCHours(0, 0, 0, 0)
  date.setUTCFullYear(year, month - 1, day)
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    throw new RangeError(`Invalid date key: ${dateKey}`)
  }

  return Math.trunc(date.getTime() / MILLISECONDS_PER_DAY)
}

export function getDateKeyInTimeZone(instant: Date, timeZone: string): string {
  if (!(instant instanceof Date) || !Number.isFinite(instant.getTime())) {
    throw new RangeError('Invalid instant')
  }
  if (typeof timeZone !== 'string' || timeZone.trim() !== timeZone || timeZone === '') {
    throw new RangeError('Invalid time zone')
  }

  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(instant)
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]))
  const dateKey = `${values.year}-${values.month}-${values.day}`
  dateKeyToEpochDay(dateKey)
  return dateKey
}

export function getDeadlineDayStatus(dueDate: string, asOfDate: string): DeadlineDayStatus {
  const dayDelta = dateKeyToEpochDay(dueDate) - dateKeyToEpochDay(asOfDate)

  if (dayDelta < 0) {
    const daysOverdue = Math.abs(dayDelta)
    return {
      kind: 'overdue',
      dayDelta,
      label: `Overdue by ${daysOverdue} ${daysOverdue === 1 ? 'day' : 'days'}`,
    }
  }
  if (dayDelta === 0) return { kind: 'today', dayDelta, label: 'Today' }
  if (dayDelta === 1) return { kind: 'future', dayDelta, label: 'Tomorrow' }
  return { kind: 'future', dayDelta, label: `In ${dayDelta} days` }
}
