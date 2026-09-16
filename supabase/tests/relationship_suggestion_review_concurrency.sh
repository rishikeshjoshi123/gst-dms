#!/usr/bin/env bash
set -euo pipefail

db_container=${SUPABASE_DB_CONTAINER:?SUPABASE_DB_CONTAINER is required}
tmp_dir=$(mktemp -d)
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

db_psql() {
  docker exec "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -Atc "$1"
}

actor=151a0000-0000-0000-0000-000000000099
item=$(db_psql "SELECT id FROM public.review_items WHERE type='relationship_suggestion' AND status='needs_review' ORDER BY created_at LIMIT 1;" | tr -d '[:space:]')
revision=$(db_psql "SELECT revision FROM public.review_items WHERE id='$item';" | tr -d '[:space:]')
if [[ -z "$item" || -z "$revision" ]]; then
  echo "relationship decision race fixture has no current candidate" >&2
  exit 1
fi

call_resolver() {
  local key=$1
  db_psql "SELECT set_config('request.jwt.claim.role','authenticated',false); SELECT set_config('request.jwt.claim.sub','$actor',false); SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','$actor','iat',extract(epoch FROM now())::bigint)::text,false); SELECT code||':'||replayed FROM public.resolve_relationship_suggestion('$item',$revision,'reject_relationship',NULL,NULL,NULL,NULL,'Concurrent human rejection','$key');"
}

key_a=15180000-0000-0000-0000-000000000091
key_b=15180000-0000-0000-0000-000000000092
call_resolver "$key_a" >"$tmp_dir/a" & pid_a=$!
call_resolver "$key_b" >"$tmp_dir/b" & pid_b=$!
wait "$pid_a"
wait "$pid_b"
result_a=$(tail -1 "$tmp_dir/a" | tr -d '[:space:]')
result_b=$(tail -1 "$tmp_dir/b" | tr -d '[:space:]')
sorted=$(printf '%s\n%s\n' "$result_a" "$result_b" | sort | tr '\n' ' ')
if [[ "$sorted" != "ok:false stale:false " ]]; then
  echo "concurrent relationship decisions did not yield one winner and one current stale result: $result_a / $result_b" >&2
  exit 1
fi

state=$(db_psql "SELECT (SELECT count(*) FROM public.relationship_suggestion_decisions WHERE review_item_id='$item')||':'||(SELECT count(*) FROM public.activity_events WHERE event_type='review.relationship_suggestion_decided')||':'||(SELECT count(*) FROM public.document_relationships WHERE provenance='candidate')||':'||(SELECT status||':'||closure_reason||':'||revision FROM public.review_items WHERE id='$item');" | tr -d '[:space:]')
if [[ "$state" != "1:1:0:closed:decision_recorded:$((revision+1))" ]]; then
  echo "relationship race did not apply one atomic rejection effect: $state" >&2
  exit 1
fi

winner_key=$key_a
if [[ "$result_b" == "ok:false" ]]; then winner_key=$key_b; fi
replay=$(call_resolver "$winner_key" | tail -1 | tr -d '[:space:]')
if [[ "$replay" != "ok:true" ]]; then
  echo "winning relationship decision did not replay exactly: $replay" >&2
  exit 1
fi

echo "D11-T13 concurrent relationship decisions applied one atomic winner, returned current stale state to the loser, and replayed exactly."
