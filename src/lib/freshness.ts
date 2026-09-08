export function freshnessLabel(lastSuccessfulFetch: number | null, now: number, offline: boolean) {
  if (lastSuccessfulFetch === null) return offline ? 'Offline · Refresh unavailable' : 'Refresh unavailable'
  const minutes = Math.max(0, Math.floor((now - lastSuccessfulFetch) / 60_000))
  const age = minutes < 1 ? 'Refreshed just now' : `Refreshed ${minutes} min ago`
  return offline ? `Offline · ${age}` : age
}
