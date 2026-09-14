#!/usr/bin/env bash
set -euo pipefail
db_container=${SUPABASE_DB_CONTAINER:?Supply the verified disposable database container}
[[ "$db_container" == supabase_db_dms-review-* ]] || { echo 'Review concurrency requires an isolated dms-review project.' >&2; exit 1; }
result_dir=$(mktemp -d)
trap 'rm -f "$result_dir/first" "$result_dir/second"; rmdir "$result_dir"' EXIT
db_psql() { docker exec -i "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
item=$(db_psql -c "SELECT id FROM public.review_items WHERE document_id='153e0000-0000-0000-0000-000000000002';")
candidate=$(db_psql -c "SELECT candidate_id FROM public.review_item_evidence WHERE review_item_id='$item' AND ordinal=2;")
resolve() {
  db_psql -c "BEGIN; SET LOCAL statement_timeout='10s'; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='$1'; SELECT code FROM public.resolve_extraction_conflict('$item',1,'select_candidate','$candidate','Concurrent selection','$2'); COMMIT;" > "$3"
}
resolve '153a0000-0000-0000-0000-000000000001' '15390000-0000-0000-0000-000000000011' "$result_dir/first" & first_pid=$!
resolve '153a0000-0000-0000-0000-000000000003' '15390000-0000-0000-0000-000000000012' "$result_dir/second" & second_pid=$!
wait "$first_pid"; wait "$second_pid"
[[ "$(sort "$result_dir/first" "$result_dir/second" | tr '\n' ':')" == 'ok:stale:' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.review_item_decisions WHERE review_item_id='$item';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_events WHERE correlation_id='$item';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.document_field_decisions WHERE document_id='153e0000-0000-0000-0000-000000000002';")" == '2' ]]
echo 'Concurrent Review decisions produced one closed result, two field decisions, one Review decision and one Activity event.'

item=$(db_psql -c "SELECT id FROM public.review_items WHERE document_id='153e0000-0000-0000-0000-000000000003';")
sql="BEGIN; SET LOCAL statement_timeout='10s'; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='153a0000-0000-0000-0000-000000000001'; SELECT code FROM public.resolve_extraction_conflict('$item',1,'request_clarification',NULL,'Clarify conflicting evidence','15390000-0000-0000-0000-000000000013'); COMMIT;"
db_psql -c "$sql" > "$result_dir/first" & first_pid=$!
db_psql -c "$sql" > "$result_dir/second" & second_pid=$!
wait "$first_pid"; wait "$second_pid"
[[ "$(sort "$result_dir/first" "$result_dir/second" | tr '\n' ':')" == 'ok:ok:' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.review_item_decisions WHERE review_item_id='$item';")" == '1' ]]
echo 'Concurrent identical clarification replay converged on one immutable decision.'

# A concurrent source-pointer replacement closes the old item regardless of
# whether clarification committed first. No field decision can escape to a
# replacement version.
db_psql -c "BEGIN; SET LOCAL statement_timeout='10s'; UPDATE public.documents SET current_version_id=NULL WHERE id='153e0000-0000-0000-0000-000000000003'; COMMIT;" > "$result_dir/first" & first_pid=$!
db_psql -c "BEGIN; SET LOCAL statement_timeout='10s'; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='153a0000-0000-0000-0000-000000000003'; SELECT code FROM public.resolve_extraction_conflict('$item',2,'request_clarification',NULL,'Racing source replacement','15390000-0000-0000-0000-000000000014'); COMMIT;" > "$result_dir/second" & second_pid=$!
wait "$first_pid"; wait "$second_pid"
[[ "$(cat "$result_dir/second")" =~ ^(ok|stale)$ ]]
[[ "$(db_psql -c "SELECT status::text||':'||closure_reason::text FROM public.review_items WHERE id='$item';")" == 'closed:source_replaced' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.document_field_decisions WHERE document_id='153e0000-0000-0000-0000-000000000003';")" == '0' ]]
echo 'Concurrent source replacement left the old Review closed without field decisions.'

# The recovery resolver has its own typed payload but shares the same serialized
# Review/document boundary: exactly one actor may materialize manual facts.
item=$(db_psql -c "SELECT id FROM public.review_items WHERE document_id='153e0000-0000-0000-0000-000000000009' AND type='processing_recovery';")
metadata='{"doc_type":"OIO","reference_number":"OIO/CONCURRENT/9","document_date":"2026-09-15","direction":"incoming","issued_by":"GST Authority"}'
recover() {
  db_psql -c "BEGIN; SET LOCAL statement_timeout='10s'; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='$1'; SELECT code FROM public.resolve_processing_recovery('$item',1,'continue_manual','$metadata','Concurrent manual verification','$2'); COMMIT;" > "$3"
}
recover '153a0000-0000-0000-0000-000000000001' '15790000-0000-0000-0000-000000000011' "$result_dir/first" & first_pid=$!
recover '153a0000-0000-0000-0000-000000000003' '15790000-0000-0000-0000-000000000012' "$result_dir/second" & second_pid=$!
wait "$first_pid"; wait "$second_pid"
[[ "$(sort "$result_dir/first" "$result_dir/second" | tr '\n' ':')" == 'ok:stale:' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.document_field_candidates WHERE manual_review_item_id='$item';")" == '5' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.review_item_decisions WHERE review_item_id='$item';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_events WHERE correlation_id='$item';")" == '1' ]]
echo 'Concurrent manual recovery produced one closed decision, five effective manual facts and one Activity event.'
