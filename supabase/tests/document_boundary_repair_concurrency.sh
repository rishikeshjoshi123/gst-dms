#!/usr/bin/env bash
set -euo pipefail
db_container="${SUPABASE_DB_CONTAINER:?local database container required}"
[[ "$db_container" == 'supabase_db_dms' ]] || { echo 'Refusing non-project database'; exit 1; }
result_dir="$(mktemp -d /tmp/dms-boundary-repair.XXXXXX)"
trap 'rm -f "$result_dir/first" "$result_dir/second"; rmdir "$result_dir"' EXIT
db_psql() { docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
actor='152a0000-0000-0000-0000-000000000001'
target='152d0000-0000-0000-0000-000000000002'
document='152e0000-0000-0000-0000-000000000004'
fingerprint=$(db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='$actor'; SELECT public.preview_document_boundary_repair('$document','$target','copy')->>'fingerprint'; COMMIT;")
[[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]]
run_copy() {
  local user_id="$1" request_key="$2" output="$3"
  db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='$user_id'; SELECT public.execute_document_boundary_repair('$document','$target','copy','$fingerprint','Shared source repair','$request_key')->>'code'; COMMIT;" > "$output"
}
run_copy "$actor" '15290000-0000-0000-0000-000000000001' "$result_dir/first" &
first_pid=$!
run_copy '152a0000-0000-0000-0000-000000000006' '15290000-0000-0000-0000-000000000002' "$result_dir/second" &
second_pid=$!
wait "$first_pid"; wait "$second_pid"
[[ "$(sort "$result_dir/first" "$result_dir/second" | tr '\n' ':')" == 'blocked:ok:' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.documents WHERE copied_from_document_id='$document';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.document_boundary_repair_receipts WHERE source_document_id='$document';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.outbox_events WHERE idempotency_key LIKE 'document.repair.search.%' AND aggregate_id IN(SELECT id FROM public.documents WHERE copied_from_document_id='$document');")" == '1' ]]
echo 'Concurrent shared-source Copy produced one logical copy, receipt and Search intent.'

# Same-key simultaneous Move must replay the committed result, preserving one ID.
document='152e0000-0000-0000-0000-000000000001'
fingerprint=$(db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='$actor'; SELECT public.preview_document_boundary_repair('$document','$target','move')->>'fingerprint'; COMMIT;")
[[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]]
move_sql="BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='$actor'; SELECT public.execute_document_boundary_repair('$document','$target','move','$fingerprint','Exclusive proceeding repair','15290000-0000-0000-0000-000000000003')->>'code'; COMMIT;"
db_psql -c "$move_sql" > "$result_dir/first" &
first_pid=$!
db_psql -c "$move_sql" > "$result_dir/second" &
second_pid=$!
wait "$first_pid"; wait "$second_pid"
[[ "$(sort "$result_dir/first" "$result_dir/second" | tr '\n' ':')" == 'ok:ok:' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.document_boundary_repair_receipts WHERE idempotency_key='15290000-0000-0000-0000-000000000003';")" == '1' ]]
echo 'Concurrent same-key Move converged on one receipt.'

# A preview may fence its exact dependencies, but must not lock whole tables.
document='152e0000-0000-0000-0000-000000000002'
db_psql -c "INSERT INTO public.clients(id,org_id,name) VALUES('152c0000-0000-0000-0000-000000000002','152b0000-0000-0000-0000-000000000002','Other tenant'); INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES('152d0000-0000-0000-0000-000000000003','152b0000-0000-0000-0000-000000000002','152c0000-0000-0000-0000-000000000002','Other proceeding','OTHER-152');"
fingerprint=$(db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='$actor'; SELECT public.preview_document_boundary_repair('$document','$target','copy')->>'fingerprint'; COMMIT;")
db_psql -c "BEGIN; SET LOCAL application_name='boundary_scope_holder'; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='$actor'; SELECT public.preview_document_boundary_repair('$document','$target','copy')->>'code'; SELECT pg_sleep(3); COMMIT;" > "$result_dir/first" &
first_pid=$!
for attempt in {1..50}; do
  [[ "$(db_psql -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='boundary_scope_holder' AND wait_event='PgSleep';")" == '1' ]] && break
  sleep 0.05
done
[[ "$(db_psql -c "BEGIN; SET LOCAL lock_timeout='500ms'; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='152a0000-0000-0000-0000-000000000004'; SELECT code FROM public.create_note_with_optional_task('152d0000-0000-0000-0000-000000000003','Unrelated ordinary action','general',true,'15290000-0000-0000-0000-000000000006'); COMMIT;")" == 'ok' ]]
db_psql -c "BEGIN; SET LOCAL lock_timeout='500ms'; UPDATE public.document_processing_runs SET completed_at=clock_timestamp() WHERE id='15210000-0000-0000-0000-000000000003'; COMMIT;"
if db_psql -c "BEGIN; SET LOCAL lock_timeout='500ms'; UPDATE public.document_processing_runs SET completed_at=clock_timestamp() WHERE id='15210000-0000-0000-0000-000000000002'; COMMIT;" > "$result_dir/second" 2>&1; then
  echo 'Exact document processing raced an unfenced preview'; exit 1
fi
wait "$first_pid"
db_psql -c "UPDATE public.document_processing_runs SET completed_at=clock_timestamp() WHERE id='15210000-0000-0000-0000-000000000002';"
[[ "$(db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='$actor'; SELECT public.execute_document_boundary_repair('$document','$target','copy','$fingerprint','Stale ordinary processing','15290000-0000-0000-0000-000000000007')->>'code'; COMMIT;")" == 'stale_preview' ]]
echo 'Scoped preview allowed cross-tenant note/task Activity and unrelated processing; exact processing serialized and invalidated preview.'
