/**
 * Retired manual reprocess entry point.
 *
 * Reprocessing must be expressed as an explicit, scoped database command that
 * writes a safe outbox event. This script intentionally has no credentials,
 * document IDs, storage paths, or Trigger task dispatch.
 */
console.error('Retired: use the future scoped durable reprocess command.')
process.exitCode = 1
