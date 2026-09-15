#!/usr/bin/env bash
set -euo pipefail

container=${SUPABASE_DB_CONTAINER:?Exclusively owned disposable database container required}
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -r "$tmp_dir"' EXIT

docker exec -i "$container" psql -X -At -v ON_ERROR_STOP=1 -U postgres -d postgres \
  < "$repo_root/supabase/tests/document_processing_source_concurrency_claim.sql" \
  > "$tmp_dir/claim.out" 2> "$tmp_dir/claim.err" &
claim_pid=$!

for attempt in {1..40}; do
  if rg -q '^claimed$' "$tmp_dir/claim.out"; then break; fi
  if ! kill -0 "$claim_pid" 2>/dev/null; then break; fi
  sleep 0.1
done
if ! rg -q '^claimed$' "$tmp_dir/claim.out"; then
  wait "$claim_pid" || true
  printf 'Transactional begin did not claim before concurrent Trash.\n' >&2
  exit 1
fi

start_seconds=$(date +%s)
docker exec -i "$container" psql -X -At -v ON_ERROR_STOP=1 -U postgres -d postgres \
  < "$repo_root/supabase/tests/document_processing_source_concurrency_trash.sql" \
  > "$tmp_dir/trash.out" 2> "$tmp_dir/trash.err"
elapsed_seconds=$(( $(date +%s) - start_seconds ))
wait "$claim_pid"
if (( elapsed_seconds < 1 )) || ! rg -q '^source_unavailable\|$' "$tmp_dir/trash.out"; then
  printf 'Concurrent Trash was not fenced by transactional begin, or post-Trash grant leaked source.\n' >&2
  exit 1
fi
printf 'Concurrent Trash waited %s seconds for begin transaction; later grant denied source.\n' "$elapsed_seconds"
