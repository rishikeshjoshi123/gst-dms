#!/usr/bin/env bash
set -euo pipefail

operation_id="$1"
db_container="${SUPABASE_DB_CONTAINER:-supabase_db_dms}"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

db_psql() {
  docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"
}

# Restore holds the organisation/SHA transaction lock after the function
# returns. The production writer must remain fenced until Restore commits,
# then re-read the now-active reference and reject its new logical document.
db_psql -c "
  BEGIN;
  SET LOCAL \"request.jwt.claim.sub\"='89100000-0000-0000-0000-000000000001';
  SET LOCAL \"request.jwt.claim.role\"='authenticated';
  SELECT code FROM public.restore_trash_operation('$operation_id','restore.fixture.writer-race');
  SELECT pg_sleep(2);
  COMMIT;" > "$temp_dir/restore" &
restore_pid=$!
sleep 0.2
writer_started="$(date +%s)"
db_psql -c "
  BEGIN;
  SET LOCAL \"request.jwt.claim.sub\"='89100000-0000-0000-0000-000000000001';
  SET LOCAL \"request.jwt.claim.role\"='authenticated';
  SELECT code FROM public.assign_intake_to_new_document(
    '89500000-0000-0000-0000-000000000001',
    '89300000-0000-0000-0000-000000000001',
    'Writer race',
    '89100000-0000-0000-0000-000000000001',
    '89600000-0000-0000-0000-000000000001'
  );
  COMMIT;" > "$temp_dir/writer"
writer_elapsed="$(( $(date +%s) - writer_started ))"
wait "$restore_pid"

rg -q '^restored$' "$temp_dir/restore"
rg -q '^duplicate_reference$' "$temp_dir/writer"
if (( writer_elapsed < 1 )); then
  echo 'Writer did not wait on the Restore SHA fence.' >&2
  exit 1
fi

active_sha_references="$(db_psql -c "
  SELECT count(DISTINCT version.document_id)
  FROM public.document_versions version
  JOIN public.file_assets asset ON asset.org_id=version.org_id AND asset.id=version.asset_id
  JOIN public.documents document ON document.org_id=version.org_id AND document.id=version.document_id
  WHERE version.org_id='89000000-0000-0000-0000-000000000001'
    AND asset.sha256=repeat('f',64)
    AND version.validation_state='valid' AND version.state IN ('current','superseded')
    AND document.record_state='active' AND document.deleted_at IS NULL;")"
[[ "$active_sha_references" == '1' ]]

echo 'Restore-vs-writer SHA fence passed with one active logical PDF reference.'
