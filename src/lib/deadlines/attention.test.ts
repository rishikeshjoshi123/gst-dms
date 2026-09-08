import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import { getDateKeyInTimeZone, getDeadlineDayStatus } from './attention'

describe('getDeadlineDayStatus', () => {
  it('labels yesterday, today, and tomorrow without negative future-style counts', () => {
    assert.deepEqual(getDeadlineDayStatus('2026-09-07', '2026-09-08'), {
      kind: 'overdue',
      dayDelta: -1,
      label: 'Overdue by 1 day',
    })
    assert.deepEqual(getDeadlineDayStatus('2026-09-08', '2026-09-08'), {
      kind: 'today',
      dayDelta: 0,
      label: 'Today',
    })
    assert.deepEqual(getDeadlineDayStatus('2026-09-09', '2026-09-08'), {
      kind: 'future',
      dayDelta: 1,
      label: 'Tomorrow',
    })
  })

  it('labels multi-day past and future dates explicitly', () => {
    assert.equal(getDeadlineDayStatus('2026-08-30', '2026-09-08').label, 'Overdue by 9 days')
    assert.equal(getDeadlineDayStatus('2026-09-18', '2026-09-08').label, 'In 10 days')
  })

  it('handles month and year rollovers as calendar days', () => {
    assert.equal(getDeadlineDayStatus('2027-01-01', '2026-12-31').label, 'Tomorrow')
    assert.equal(getDeadlineDayStatus('2026-02-28', '2026-03-01').label, 'Overdue by 1 day')
  })

  it('handles leap-day boundaries', () => {
    assert.equal(getDeadlineDayStatus('2028-02-29', '2028-02-28').label, 'Tomorrow')
    assert.equal(getDeadlineDayStatus('2028-03-01', '2028-02-28').label, 'In 2 days')
  })

  it('rejects malformed and impossible date keys', () => {
    for (const invalid of ['2026-2-03', '2026-02-30', '2025-02-29', '2026-13-01', '2026-01-01T00:00:00Z']) {
      assert.throws(() => getDeadlineDayStatus(invalid, '2026-01-01'), RangeError)
    }
    assert.throws(() => getDeadlineDayStatus('2026-01-01', 'not-a-date'), RangeError)
  })
})

describe('getDateKeyInTimeZone', () => {
  it('derives the owning date on opposite sides of the international date line', () => {
    const instant = new Date('2026-09-08T10:30:00.000Z')
    assert.equal(getDateKeyInTimeZone(instant, 'Pacific/Kiritimati'), '2026-09-09')
    assert.equal(getDateKeyInTimeZone(instant, 'America/Adak'), '2026-09-08')
  })

  it('rejects invalid instants and timezones instead of applying a fallback', () => {
    assert.throws(() => getDateKeyInTimeZone(new Date(Number.NaN), 'Asia/Kolkata'), RangeError)
    assert.throws(() => getDateKeyInTimeZone(new Date(), 'Not/A_Timezone'), RangeError)
    assert.throws(() => getDateKeyInTimeZone(new Date(), ' Asia/Kolkata'), RangeError)
  })
})
