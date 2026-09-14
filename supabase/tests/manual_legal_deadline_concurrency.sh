#!/bin/sh
set -eu
container="${SUPABASE_DB_CONTAINER:?SUPABASE_DB_CONTAINER is required}"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
sql_prefix="SET ROLE authenticated; SET request.jwt.claim.role='authenticated'; SET request.jwt.claim.sub='a1590000-0000-0000-0000-000000000101';"
create_sql="$sql_prefix SELECT code||':'||replayed FROM public.create_manual_legal_deadline('d1590000-0000-0000-0000-000000000101','Concurrent create','One obligation','reply_due','2028-03-01','Concurrent manual basis','f1590000-0000-0000-0000-000000000102');"
docker exec "$container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "$create_sql" >"$scratch/create-a" & a=$!
docker exec "$container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "$create_sql" >"$scratch/create-b" & b=$!
wait "$a"; wait "$b"
test "$(grep -c '^ok:' "$scratch/create-a")" -eq 1
test "$(grep -c '^ok:' "$scratch/create-b")" -eq 1
test "$(docker exec "$container" psql -X -qAt -U postgres -d postgres -c "SELECT count(*) FROM public.deadline_command_receipts WHERE idempotency_key='f1590000-0000-0000-0000-000000000102'")" -eq 1
deadline="$(docker exec "$container" psql -X -qAt -U postgres -d postgres -c "SELECT deadline_id FROM public.deadline_command_receipts WHERE idempotency_key='f1590000-0000-0000-0000-000000000101'")"
amend_a="$sql_prefix SELECT code FROM public.amend_manual_legal_deadline('$deadline',1,'Amend A','Obligation A','other_legal','2028-03-02','Basis A','Concurrent correction A','f1590000-0000-0000-0000-000000000103');"
amend_b="$sql_prefix SELECT code FROM public.amend_manual_legal_deadline('$deadline',1,'Amend B','Obligation B','other_legal','2028-03-03','Basis B','Concurrent correction B','f1590000-0000-0000-0000-000000000104');"
docker exec "$container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "$amend_a" >"$scratch/amend-a" & a=$!
docker exec "$container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "$amend_b" >"$scratch/amend-b" & b=$!
wait "$a"; wait "$b"
test "$(grep -h -E '^(ok|stale_revision)$' "$scratch/amend-a" "$scratch/amend-b" | sort | tr '\n' ' ')" = "ok stale_revision "
test "$(docker exec "$container" psql -X -qAt -U postgres -d postgres -c "SELECT count(*) FROM public.deadline_versions WHERE deadline_id='$deadline'")" -eq 2
echo "manual legal deadline concurrency passed"
