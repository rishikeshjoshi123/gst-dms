#!/usr/bin/env bash
set -euo pipefail

# Run only after `supabase db reset --local --no-seed` on a disposable database.
# A new-document assignment races attachment of the same ready-PDF asset to a
# metadata-only record. The organisation/SHA fence must allow exactly one
# logical-document materialisation; 00082's focused SQL fixture covers the
# matching replace and service-only intended-assignment writer results.
db_container="$(docker ps --format '{{.Names}}' | rg 'supabase_db_.*dms' | head -n1)"
if [[ -z "$db_container" ]]; then
  echo 'Local Supabase database container not found.' >&2
  exit 1
fi

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
docker exec -i "$db_container" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres \
  < "$root_dir/supabase/tests/exact_pdf_duplicate_trash_fence_concurrency_setup.sql"

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "
  BEGIN;
  SELECT set_config('request.jwt.claim.sub','83100000-0000-0000-0000-000000000001',true);
  SELECT set_config('request.jwt.claim.role','authenticated',true);
  SELECT code FROM public.assign_intake_to_new_document('83500000-0000-0000-0000-000000000001','83300000-0000-0000-0000-000000000001','Race A','83100000-0000-0000-0000-000000000001','83600000-0000-0000-0000-000000000001');
  SELECT pg_sleep(1);
  COMMIT;" > "$temp_dir/a" &
first_pid=$!
sleep 0.1
docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "
  BEGIN;
  SELECT set_config('request.jwt.claim.sub','83100000-0000-0000-0000-000000000001',true);
  SELECT set_config('request.jwt.claim.role','authenticated',true);
  SELECT code FROM public.attach_intake_to_document('83800000-0000-0000-0000-000000000001','83500000-0000-0000-0000-000000000002',(SELECT lifecycle_revision FROM public.documents WHERE id='83800000-0000-0000-0000-000000000001'),'83100000-0000-0000-0000-000000000001','83600000-0000-0000-0000-000000000002');
  COMMIT;" > "$temp_dir/b"
wait "$first_pid"

if ! rg -q '^ok$' "$temp_dir/a" || ! rg -q '^duplicate_reference$' "$temp_dir/b"; then
  echo 'Expected one ok and one duplicate_reference result.' >&2
  cat "$temp_dir/a" "$temp_dir/b" >&2
  exit 1
fi
count="$(docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "SELECT count(*) FROM public.document_versions WHERE org_id='83000000-0000-0000-0000-000000000001' AND asset_id='83400000-0000-0000-0000-000000000001' AND validation_state='valid' AND state IN ('current','superseded');")"
[[ "$count" == '1' ]]
replay="$(docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "BEGIN; SELECT set_config('request.jwt.claim.sub','83100000-0000-0000-0000-000000000001',true); SELECT set_config('request.jwt.claim.role','authenticated',true); SELECT code FROM public.assign_intake_to_new_document('83500000-0000-0000-0000-000000000001','83300000-0000-0000-0000-000000000001','Race A','83100000-0000-0000-0000-000000000001','83600000-0000-0000-0000-000000000001'); COMMIT;")"
[[ "$replay" == 'ok' ]]

# Each second caller begins while the first transaction holds the same
# actor/key fence. Its revision snapshot is intentionally stale by the time
# the first commits, so only a durable replay (not ordinary validation) can
# return the original successful result.
docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "
  BEGIN;
  SET LOCAL \"request.jwt.claim.sub\" = '83100000-0000-0000-0000-000000000001';
  SET LOCAL \"request.jwt.claim.role\" = 'authenticated';
  SELECT code || '|' || document_version_id::text || '|' || lifecycle_revision::text
  FROM public.attach_intake_to_document('83800000-0000-0000-0000-000000000002','83500000-0000-0000-0000-000000000003',(SELECT lifecycle_revision FROM public.documents WHERE id='83800000-0000-0000-0000-000000000002'),'83100000-0000-0000-0000-000000000001','83600000-0000-0000-0000-000000000003');
  SELECT pg_sleep(1);
  COMMIT;" > "$temp_dir/attach-a" &
attach_first_pid=$!
sleep 0.1
docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "
  BEGIN;
  SET LOCAL \"request.jwt.claim.sub\" = '83100000-0000-0000-0000-000000000001';
  SET LOCAL \"request.jwt.claim.role\" = 'authenticated';
  SELECT code || '|' || document_version_id::text || '|' || lifecycle_revision::text
  FROM public.attach_intake_to_document('83800000-0000-0000-0000-000000000002','83500000-0000-0000-0000-000000000003',(SELECT lifecycle_revision FROM public.documents WHERE id='83800000-0000-0000-0000-000000000002'),'83100000-0000-0000-0000-000000000001','83600000-0000-0000-0000-000000000003');
  COMMIT;" > "$temp_dir/attach-b"
wait "$attach_first_pid"
attach_first="$(rg '^ok\|[0-9a-f-]+\|[0-9]+$' "$temp_dir/attach-a")"
attach_second="$(rg '^ok\|[0-9a-f-]+\|[0-9]+$' "$temp_dir/attach-b")"
if [[ -z "$attach_first" || "$attach_first" != "$attach_second" ]]; then
  echo 'Same-key attach did not replay the original successful result.' >&2
  cat "$temp_dir/attach-a" "$temp_dir/attach-b" >&2
  exit 1
fi
attach_count="$(docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "SELECT count(*) FROM public.document_versions WHERE document_id='83800000-0000-0000-0000-000000000002';")"
[[ "$attach_count" == '1' ]]

docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "
  BEGIN;
  SET LOCAL \"request.jwt.claim.sub\" = '83100000-0000-0000-0000-000000000001';
  SET LOCAL \"request.jwt.claim.role\" = 'authenticated';
  SELECT code || '|' || document_version_id::text || '|' || lifecycle_revision::text
  FROM public.replace_document_version('83800000-0000-0000-0000-000000000003','83500000-0000-0000-0000-000000000004',(SELECT lifecycle_revision FROM public.documents WHERE id='83800000-0000-0000-0000-000000000003'),'concurrent replay','83100000-0000-0000-0000-000000000001','83600000-0000-0000-0000-000000000004');
  SELECT pg_sleep(1);
  COMMIT;" > "$temp_dir/replace-a" &
replace_first_pid=$!
sleep 0.1
docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "
  BEGIN;
  SET LOCAL \"request.jwt.claim.sub\" = '83100000-0000-0000-0000-000000000001';
  SET LOCAL \"request.jwt.claim.role\" = 'authenticated';
  SELECT code || '|' || document_version_id::text || '|' || lifecycle_revision::text
  FROM public.replace_document_version('83800000-0000-0000-0000-000000000003','83500000-0000-0000-0000-000000000004',(SELECT lifecycle_revision FROM public.documents WHERE id='83800000-0000-0000-0000-000000000003'),'concurrent replay','83100000-0000-0000-0000-000000000001','83600000-0000-0000-0000-000000000004');
  COMMIT;" > "$temp_dir/replace-b"
wait "$replace_first_pid"
replace_first="$(rg '^ok\|[0-9a-f-]+\|[0-9]+$' "$temp_dir/replace-a")"
replace_second="$(rg '^ok\|[0-9a-f-]+\|[0-9]+$' "$temp_dir/replace-b")"
if [[ -z "$replace_first" || "$replace_first" != "$replace_second" ]]; then
  echo 'Same-key replace did not replay the original successful result.' >&2
  cat "$temp_dir/replace-a" "$temp_dir/replace-b" >&2
  exit 1
fi
replace_count="$(docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "SELECT count(*) FROM public.document_versions WHERE document_id='83800000-0000-0000-0000-000000000003';")"
[[ "$replace_count" == '2' ]]

echo 'Exact-PDF cross-writer and same-key attach/replace concurrency fences passed.'
