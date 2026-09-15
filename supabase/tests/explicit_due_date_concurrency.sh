#!/usr/bin/env bash
set -euo pipefail
db_container=${SUPABASE_DB_CONTAINER:?Supply the verified disposable database container}
[[ "$db_container" == 'supabase_db_dms-explicit-due-165' ]] || {
  echo 'Due-date concurrency requires the isolated dms-explicit-due-165 project.' >&2; exit 1;
}
scratch=$(mktemp -d)
trap 'rm -f "$scratch/first" "$scratch/second"; rmdir "$scratch"' EXIT
db_psql(){ docker exec -i "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
item=$(db_psql -c "SELECT id FROM public.review_items WHERE type='deadline_verification' AND semantic_candidate_key='legal_date:browser-source';")
deadline=$(db_psql -c "SELECT b.deadline_id FROM public.deadline_candidate_bindings b JOIN public.review_item_evidence e ON e.candidate_id=b.candidate_id WHERE e.review_item_id='$item';")
[[ "$item" =~ ^[0-9a-f-]{36}$ && "$deadline" =~ ^[0-9a-f-]{36}$ ]] || exit 1
resolve(){
  db_psql -c "BEGIN; SET LOCAL statement_timeout='10s'; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.sub\"='$1'; SELECT code FROM public.resolve_explicit_due_date_review('$item',1,'$2',NULL,'Concurrent source-grounded decision','$3'); COMMIT;" >"$4"
}
resolve '153a0000-0000-0000-0000-000000000001' 'verify' '16590000-0000-0000-0000-000000000011' "$scratch/first" & first=$!
resolve '153a0000-0000-0000-0000-000000000003' 'reject' '16590000-0000-0000-0000-000000000012' "$scratch/second" & second=$!
wait "$first"; wait "$second"
[[ "$(sort "$scratch/first" "$scratch/second" | tr '\n' ':')" == 'ok:stale:' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.deadline_candidate_decisions WHERE deadline_id='$deadline';")" == '1' ]]
[[ "$(db_psql -c "SELECT current_revision FROM public.deadlines WHERE id='$deadline';")" == '2' ]]
[[ "$(db_psql -c "SELECT status::text||':'||revision FROM public.review_items WHERE id='$item';")" == 'closed:2' ]]
echo 'Concurrent legal-date Review produced one human winner and one stale loser.'
