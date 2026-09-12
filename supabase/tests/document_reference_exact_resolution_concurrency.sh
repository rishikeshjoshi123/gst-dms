#!/usr/bin/env bash
set -euo pipefail

db_container=${SUPABASE_DB_CONTAINER:?SUPABASE_DB_CONTAINER is required}
tmp_dir=$(mktemp -d)
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

db_psql() {
  docker exec "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -Atc "$1"
}

org=151b0000-0000-0000-0000-000000000099
actor=151a0000-0000-0000-0000-000000000099
source_doc=151e0000-0000-0000-0000-000000000098
target_doc=151e0000-0000-0000-0000-000000000099
binding_id=$(db_psql "SELECT id FROM public.document_version_analysis_bindings WHERE document_id='$source_doc';" | tr -d '[:space:]')
late_candidate=$(db_psql "SELECT id FROM public.document_field_candidates WHERE document_id='$target_doc' AND normalized_value->>'normalized_value'='GST/703/2026';" | tr -d '[:space:]')

# Later mention and later verification may arrive in either commit order. Both
# synchronous hooks serialize on the exact key and the committed projection
# must converge to the verified target. Revoke and remove only disposable race
# projections between iterations so several scheduler orderings are exercised.
for iteration in $(seq 1 6); do
  activate_key=$(printf '15160000-0000-0000-0100-%012d' "$iteration")
  db_psql "SELECT public.materialize_document_reference_mentions('$binding_id','race.mention-target.$iteration');" >"$tmp_dir/mention.$iteration" &
  pid_a=$!
  db_psql "SELECT set_config('request.jwt.claim.role','authenticated',false); SELECT set_config('request.jwt.claim.sub','$actor',false); SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','$actor','iat',extract(epoch FROM now())::bigint)::text,false); SELECT identifier_id FROM public.activate_document_self_identifier('$late_candidate',(SELECT lifecycle_revision FROM public.documents WHERE id='$target_doc'),NULL,'$activate_key');" >"$tmp_dir/target.$iteration" &
  pid_b=$!
  wait "$pid_a"
  wait "$pid_b"
  late_ok=$(db_psql "SELECT count(*)=1 AND bool_and(c.outcome='unique_exact' AND c.target_document_id='$target_doc') FROM public.document_reference_mentions m JOIN public.current_document_reference_resolutions c ON c.org_id=m.org_id AND c.mention_id=m.id WHERE m.org_id='$org' AND m.normalized_value='GST/703/2026';" | tr -d '[:space:]')
  if [[ "$late_ok" != "t" ]]; then
    echo "mention-versus-target race did not converge on iteration $iteration" >&2
    exit 1
  fi
  if [[ "$iteration" != "6" ]]; then
    late_identifier=$(db_psql "SELECT id FROM public.document_self_identifiers WHERE org_id='$org' AND normalized_value='GST/703/2026' AND lifecycle_state='active';" | tr -d '[:space:]')
    revoke_key=$(printf '15160000-0000-0000-0101-%012d' "$iteration")
    db_psql "SELECT set_config('request.jwt.claim.role','authenticated',false); SELECT set_config('request.jwt.claim.sub','$actor',false); SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','$actor','iat',extract(epoch FROM now())::bigint)::text,false); SELECT code FROM public.revoke_document_self_identifier('$late_identifier',1,(SELECT lifecycle_revision FROM public.documents WHERE id='$target_doc'),'Repeat race setup','$revoke_key');" >/dev/null
    db_psql "SELECT set_config('casechain.document_reference_internal','on',false); DELETE FROM public.current_document_reference_resolutions WHERE mention_id IN (SELECT id FROM public.document_reference_mentions WHERE org_id='$org' AND normalized_value='GST/703/2026'); DELETE FROM public.document_reference_resolution_results WHERE mention_id IN (SELECT id FROM public.document_reference_mentions WHERE org_id='$org' AND normalized_value='GST/703/2026'); DELETE FROM public.document_reference_resolution_runs WHERE org_id='$org' AND normalized_value='GST/703/2026'; DELETE FROM public.document_reference_mentions WHERE org_id='$org' AND normalized_value='GST/703/2026';" >/dev/null
  fi
done

# A correction racing an explicit resolution of the predecessor key must leave
# the predecessor unresolved after both commits, never resurrected by a stale
# resolver result.
old_candidate=$(db_psql "SELECT id FROM public.document_field_candidates WHERE document_id='$target_doc' AND normalized_value->>'normalized_value'='GST/701/2026';" | tr -d '[:space:]')
new_candidate=$(db_psql "SELECT id FROM public.document_field_candidates WHERE document_id='$target_doc' AND normalized_value->>'normalized_value'='GST/702/2026';" | tr -d '[:space:]')
for iteration in $(seq 1 8); do
  active_identifier=$(db_psql "SELECT id FROM public.document_self_identifiers WHERE org_id='$org' AND normalized_value IN ('GST/701/2026','GST/702/2026') AND lifecycle_state='active';" | tr -d '[:space:]')
  active_value=$(db_psql "SELECT normalized_value FROM public.document_self_identifiers WHERE id='$active_identifier';" | tr -d '[:space:]')
  if [[ "$active_value" == "GST/701/2026" ]]; then next_candidate=$new_candidate; else next_candidate=$old_candidate; fi
  correction_key=$(printf '15160000-0000-0000-0200-%012d' "$iteration")
  db_psql "SELECT set_config('request.jwt.claim.role','authenticated',false); SELECT set_config('request.jwt.claim.sub','$actor',false); SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','$actor','iat',extract(epoch FROM now())::bigint)::text,false); SELECT code FROM public.correct_document_self_identifier('$active_identifier','$next_candidate',1,(SELECT lifecycle_revision FROM public.documents WHERE id='$target_doc'),NULL,'Concurrent correction','$correction_key');" >"$tmp_dir/correction.$iteration" &
  pid_a=$!
  db_psql "SELECT public.reevaluate_document_reference_exact_key('$org','RACE TRIBUNAL','order_reference','$active_value','explicit_retry','race.correction-resolution.$iteration');" >"$tmp_dir/correction_resolution.$iteration" &
  pid_b=$!
  wait "$pid_a"
  wait "$pid_b"
  if [[ "$active_value" == "GST/701/2026" ]]; then
    old_ok=$(db_psql "SELECT count(*)=1 AND bool_and(c.outcome='unresolved' AND c.target_document_id IS NULL AND c.target_identifier_id IS NULL) FROM public.document_reference_mentions m JOIN public.current_document_reference_resolutions c ON c.org_id=m.org_id AND c.mention_id=m.id WHERE m.org_id='$org' AND m.normalized_value='GST/701/2026';" | tr -d '[:space:]')
    if [[ "$old_ok" != "t" ]]; then echo "correction-versus-resolution retained a stale target on iteration $iteration" >&2; exit 1; fi
  fi
done

# Trash and explicit resolution also serialize through the exact-key hooks. A
# resolver that began first cannot leave a target current after Trash commits.
for iteration in $(seq 1 8); do
  db_psql "UPDATE public.documents SET record_state='trashed',deleted_at=now(),trashed_at=now(),trashed_by='$actor',lifecycle_revision=lifecycle_revision+1 WHERE id='$target_doc';" >"$tmp_dir/trash.$iteration" &
  pid_a=$!
  db_psql "SELECT public.reevaluate_document_reference_exact_key('$org','RACE TRIBUNAL','order_reference','GST/703/2026','explicit_retry','race.trash-resolution.$iteration');" >"$tmp_dir/trash_resolution.$iteration" &
  pid_b=$!
  wait "$pid_a"
  wait "$pid_b"
  trash_ok=$(db_psql "SELECT count(*)=1 AND bool_and(c.outcome='unresolved' AND c.target_document_id IS NULL AND c.target_identifier_id IS NULL) FROM public.document_reference_mentions m JOIN public.current_document_reference_resolutions c ON c.org_id=m.org_id AND c.mention_id=m.id WHERE m.org_id='$org' AND m.normalized_value='GST/703/2026';" | tr -d '[:space:]')
  if [[ "$trash_ok" != "t" ]]; then echo "Trash-versus-resolution retained a stale target on iteration $iteration" >&2; exit 1; fi
  db_psql "UPDATE public.documents SET record_state='active',deleted_at=NULL,trashed_at=NULL,trashed_by=NULL,restored_at=now(),lifecycle_revision=lifecycle_revision+1 WHERE id='$target_doc';" >/dev/null
done

# Two different documents swap two exact keys concurrently. Corrections lock
# the distinct old/new key pair in normalized tuple order, so neither command
# can hold one key while waiting for the other.
swap_a=151e0000-0000-0000-0000-000000000096
swap_b=151e0000-0000-0000-0000-000000000097
swap_a_old=$(db_psql "SELECT id FROM public.document_field_candidates WHERE document_id='$swap_a' AND normalized_value->>'normalized_value'='GST/701/2026';" | tr -d '[:space:]')
swap_b_old=$(db_psql "SELECT id FROM public.document_field_candidates WHERE document_id='$swap_b' AND normalized_value->>'normalized_value'='GST/702/2026';" | tr -d '[:space:]')
db_psql "SELECT set_config('request.jwt.claim.role','authenticated',false); SELECT set_config('request.jwt.claim.sub','$actor',false); SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','$actor','iat',extract(epoch FROM now())::bigint)::text,false); SELECT code FROM public.activate_document_self_identifier('$swap_a_old',(SELECT lifecycle_revision FROM public.documents WHERE id='$swap_a'),NULL,'15160000-0000-0000-0300-000000000001');" >/dev/null
db_psql "SELECT set_config('request.jwt.claim.role','authenticated',false); SELECT set_config('request.jwt.claim.sub','$actor',false); SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','$actor','iat',extract(epoch FROM now())::bigint)::text,false); SELECT code FROM public.activate_document_self_identifier('$swap_b_old',(SELECT lifecycle_revision FROM public.documents WHERE id='$swap_b'),NULL,'15160000-0000-0000-0300-000000000002');" >/dev/null
for iteration in $(seq 1 6); do
  swap_a_identifier=$(db_psql "SELECT id FROM public.document_self_identifiers WHERE document_id='$swap_a' AND lifecycle_state='active';" | tr -d '[:space:]')
  swap_b_identifier=$(db_psql "SELECT id FROM public.document_self_identifiers WHERE document_id='$swap_b' AND lifecycle_state='active';" | tr -d '[:space:]')
  swap_a_value=$(db_psql "SELECT normalized_value FROM public.document_self_identifiers WHERE id='$swap_a_identifier';" | tr -d '[:space:]')
  swap_b_value=$(db_psql "SELECT normalized_value FROM public.document_self_identifiers WHERE id='$swap_b_identifier';" | tr -d '[:space:]')
  swap_a_next=$(db_psql "SELECT id FROM public.document_field_candidates WHERE document_id='$swap_a' AND normalized_value->>'normalized_value'='$swap_b_value';" | tr -d '[:space:]')
  swap_b_next=$(db_psql "SELECT id FROM public.document_field_candidates WHERE document_id='$swap_b' AND normalized_value->>'normalized_value'='$swap_a_value';" | tr -d '[:space:]')
  swap_a_key=$(printf '15160000-0000-0000-0301-%012d' "$iteration")
  swap_b_key=$(printf '15160000-0000-0000-0302-%012d' "$iteration")
  db_psql "SELECT set_config('request.jwt.claim.role','authenticated',false); SELECT set_config('request.jwt.claim.sub','$actor',false); SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','$actor','iat',extract(epoch FROM now())::bigint)::text,false); SELECT code FROM public.correct_document_self_identifier('$swap_a_identifier','$swap_a_next',1,(SELECT lifecycle_revision FROM public.documents WHERE id='$swap_a'),NULL,'Cross-key swap','$swap_a_key');" >"$tmp_dir/swap_a.$iteration" &
  pid_a=$!
  db_psql "SELECT set_config('request.jwt.claim.role','authenticated',false); SELECT set_config('request.jwt.claim.sub','$actor',false); SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','$actor','iat',extract(epoch FROM now())::bigint)::text,false); SELECT code FROM public.correct_document_self_identifier('$swap_b_identifier','$swap_b_next',1,(SELECT lifecycle_revision FROM public.documents WHERE id='$swap_b'),NULL,'Cross-key swap','$swap_b_key');" >"$tmp_dir/swap_b.$iteration" &
  pid_b=$!
  wait "$pid_a"
  wait "$pid_b"
  swapped=$(db_psql "SELECT (SELECT normalized_value='$swap_b_value' FROM public.document_self_identifiers WHERE document_id='$swap_a' AND lifecycle_state='active') AND (SELECT normalized_value='$swap_a_value' FROM public.document_self_identifiers WHERE document_id='$swap_b' AND lifecycle_state='active');" | tr -d '[:space:]')
  if [[ "$swapped" != "t" ]]; then echo "cross-key correction swap failed on iteration $iteration" >&2; exit 1; fi
done

for iteration in $(seq 1 12); do
call="SELECT public.reevaluate_document_reference_exact_key('$org','RACE TRIBUNAL','order_reference','GST/701/2026','explicit_retry','race.same-key.$iteration');"
docker exec "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -Atc "$call" >"$tmp_dir/a" &
pid_a=$!
docker exec "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -Atc "$call" >"$tmp_dir/b" &
pid_b=$!
wait "$pid_a"
wait "$pid_b"

id_a=$(tr -d '[:space:]' <"$tmp_dir/a")
id_b=$(tr -d '[:space:]' <"$tmp_dir/b")
if [[ -z "$id_a" || "$id_a" != "$id_b" ]]; then
  echo "same-key resolver calls did not converge" >&2
  exit 1
fi
count=$(db_psql "SELECT count(*) FROM public.document_reference_resolution_runs WHERE org_id='$org' AND trigger_key='race.same-key.$iteration';" | tr -d '[:space:]')
if [[ "$count" != "1" ]]; then
  echo "same-key resolver race created $count runs" >&2
  exit 1
fi
done
echo "D09-T05 stressed mention/target (6), correction/resolution (8), Trash/resolution (8), cross-key swaps (6), and same-key (12) concurrency passed."
