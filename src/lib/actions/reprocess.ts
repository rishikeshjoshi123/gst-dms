'use server'

import { getCurrentOrgId } from './org'

export async function reprocessDocument(docId: string, isStaged: boolean = false) {
  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }
  void docId
  void isStaged
  // Reprocessing needs an explicit database command with a selected scope.
  // The legacy UI must not make a privileged Trigger task/payload choice while
  // that durable authority is still being introduced.
  return { error: 'Reprocessing is temporarily unavailable while the durable processing command is being completed.' }
}
