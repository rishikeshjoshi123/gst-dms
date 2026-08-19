export type MatterStatus =
  | 'active' | 'stayed' | 'disposed' | 'appeal_pending'
  | 'tribunal' | 'high_court' | 'supreme_court' | 'closed'

export const FINANCIAL_YEARS = [
  '2024-25', '2023-24', '2022-23', '2021-22',
  '2020-21', '2019-20', '2018-19', '2017-18', '2016-17', '2015-16', '2014-15', '2013-14',
  '2012-13', '2011-12', '2010-11', '2009-10', '2008-09',
  '2007-08', '2006-07', '2005-06', '2004-05', '2003-04', '2002-03', '2001-02', '2000-01'
]

export const MATTER_STATUS_LABELS: Record<MatterStatus, string> = {
  active: 'Active',
  stayed: 'Stayed',
  disposed: 'Disposed',
  appeal_pending: 'Appeal Pending',
  tribunal: 'At Tribunal',
  high_court: 'At High Court',
  supreme_court: 'At Supreme Court',
  closed: 'Closed',
}
