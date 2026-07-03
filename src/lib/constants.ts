export type MatterStatus =
  | 'active' | 'stayed' | 'disposed' | 'appeal_pending'
  | 'tribunal' | 'high_court' | 'supreme_court' | 'closed'

export const FINANCIAL_YEARS = [
  '2024-25', '2023-24', '2022-23', '2021-22',
  '2020-21', '2019-20', '2018-19', '2017-18',
]

export const MATTER_STATUS_LABELS: Record<MatterStatus, string> = {
  active:          'Active',
  stayed:          'Stayed',
  disposed:        'Disposed',
  appeal_pending:  'Appeal Pending',
  tribunal:        'At Tribunal',
  high_court:      'At High Court',
  supreme_court:   'At Supreme Court',
  closed:          'Closed',
}
