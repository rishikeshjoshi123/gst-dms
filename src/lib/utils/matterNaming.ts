import type { SupabaseClient } from '@supabase/supabase-js'

/**
 * Extracts acronym from client name.
 * Examples:
 * - "M/s Apex Global Industries" -> "AGI"
 * - "Reliance Industries Limited" -> "RI"
 * - "Tata Consultancy Services Pvt Ltd" -> "TCS"
 * - "Shailendra Mathur" -> "SM"
 * - "Infosys" -> "INFO"
 */
export function getClientAcronym(clientName: string): string {
  if (!clientName || typeof clientName !== 'string') return 'CASE'

  // Strip common legal prefixes & suffixes
  const cleanName = clientName
    .replace(/\b(m\/s|pvt|ltd|limited|inc|llp|co|company|corp|corporation)\b/gi, '')
    .replace(/[^a-zA-Z0-9\s]/g, '')
    .trim()

  const words = cleanName.split(/\s+/).filter(w => w.length > 0)

  if (words.length === 0) return 'CASE'

  if (words.length === 1) {
    return words[0].slice(0, 4).toUpperCase()
  }

  // Take first letter of each remaining word
  const acronym = words.map(w => w[0].toUpperCase()).join('')
  return acronym.length >= 2 ? acronym : words[0].slice(0, 4).toUpperCase()
}

/**
 * Generates default matter title according to user rule:
 * acronym of client name + fy + counter (increment if same name exists)
 *
 * Examples:
 * - AGI-2021-22-01
 * - AGI-2021-22-02 (if AGI-2021-22-01 exists)
 */
export async function generateDefaultMatterTitle(
  supabase: SupabaseClient<any>,
  orgId: string,
  clientId: string,
  clientName: string,
  financialYear: string
): Promise<string> {
  const acronym = getClientAcronym(clientName)

  // Format FY (e.g. "FY 2021-22" or "2021-22" -> "2021-22")
  let cleanFy = financialYear ? financialYear.replace(/^fy\s*/i, '').trim() : ''
  if (!cleanFy || cleanFy === 'Unknown FY') {
    cleanFy = 'GEN'
  }

  const basePattern = `${acronym}-${cleanFy}`

  // Fetch existing matter titles for this client to check collisions
  const { data: existingMatters } = await supabase
    .from('matters')
    .select('title')
    .eq('org_id', orgId)
    .eq('client_id', clientId)
    .is('deleted_at', null)

  const existingTitles = new Set((existingMatters || []).map((m: any) => m.title))

  let counter = 1
  let candidateTitle = `${basePattern}-${String(counter).padStart(2, '0')}`

  while (existingTitles.has(candidateTitle)) {
    counter++
    candidateTitle = `${basePattern}-${String(counter).padStart(2, '0')}`
  }

  return candidateTitle
}
