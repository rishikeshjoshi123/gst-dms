#!/bin/sh
set -eu
container=${SUPABASE_DB_CONTAINER:-supabase_db_dms-review-153}
query() { docker exec "$container" psql -X -Atq -U postgres -d postgres -c "$1"; }
item=$(query "SELECT id FROM public.review_items WHERE intake_id='16370000-0000-0000-0000-000000000001' AND status='needs_review'")
candidate_a=$(query "SELECT id FROM public.intake_placement_candidates WHERE matter_id='163d0000-0000-0000-0000-000000000001'")
candidate_b=$(query "SELECT id FROM public.intake_placement_candidates WHERE matter_id='163d0000-0000-0000-0000-000000000002'")
run_one() {
  member=$1 candidate=$2 key=$3 output=$4
  docker exec "$container" psql -X -Atq -v ON_ERROR_STOP=1 -U postgres -d postgres -c "BEGIN; SELECT set_config('request.jwt.claim.role','authenticated',true); SELECT set_config('request.jwt.claim.sub','$member',true); SELECT code FROM public.resolve_ambiguous_intake_placement('$item',1,'$candidate','Concurrent verified placement','$key'); COMMIT;" >"$output" &
}
left=$(mktemp) right=$(mktemp)
trap 'rm -f "$left" "$right"' EXIT
run_one 153a0000-0000-0000-0000-000000000001 "$candidate_a" 16390000-0000-0000-0000-000000000001 "$left"
pid_left=$!
run_one 153a0000-0000-0000-0000-000000000003 "$candidate_b" 16390000-0000-0000-0000-000000000002 "$right"
pid_right=$!
wait "$pid_left"; wait "$pid_right"
codes=$(printf '%s\n%s\n' "$(grep -E '^(ok|stale)$' "$left")" "$(grep -E '^(ok|stale)$' "$right")" | sort | tr '\n' ':')
test "$codes" = "ok:stale:"
test "$(query "SELECT count(*)||':'||(SELECT count(*) FROM public.review_item_decisions WHERE review_item_id='$item')||':'||(SELECT count(*) FROM public.intake_item_assignments WHERE intake_item_id='16370000-0000-0000-0000-000000000001')||':'||(SELECT count(*) FROM public.activity_events WHERE correlation_id='$item') FROM public.documents WHERE id IN(SELECT document_id FROM public.intake_item_assignments WHERE intake_item_id='16370000-0000-0000-0000-000000000001')")" = "1:1:1:1"
echo "Concurrent two-actor placement produced one canonical document/version, one Review decision, and one Activity effect."
