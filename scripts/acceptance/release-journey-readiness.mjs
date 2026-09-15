export async function authHealthIsReady(response) {
  if (response.status !== 200) return false
  const payload = await response.json().catch(() => null)
  return Boolean(payload && typeof payload === 'object' && typeof payload.version === 'string' && payload.version.length > 0)
}

export async function capturedMailIsReady(response) {
  if (response.status !== 200) return false
  const payload = await response.json().catch(() => null)
  return Array.isArray(payload) || Boolean(payload && typeof payload === 'object' && Array.isArray(payload.messages))
}
