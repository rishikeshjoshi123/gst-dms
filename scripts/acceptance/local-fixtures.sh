#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repository_root"

node_exec=${ACCEPTANCE_NODE_EXEC:-${npm_node_execpath:-}}
if [ -z "$node_exec" ]; then
  node_exec=$(command -v node)
fi
if [ ! -x "$node_exec" ] || ! "$node_exec" -e 'if (Number(process.versions.node.split(".")[0]) !== 24) process.exit(1)'; then
  echo "Local acceptance requires Node 24 exactly." >&2
  exit 1
fi

docker_bin=$(command -v docker)
supabase_bin="$repository_root/node_modules/.bin/supabase"
project_id=$(awk -F '"' '/^project_id = / { print $2; exit }' supabase/config.toml)
db_port=$(awk '/^\[db\]$/ { in_db=1; next } /^\[/ { in_db=0 } in_db && /^port = / { print $3; exit }' supabase/config.toml)

if [ -z "$project_id" ] || [ -z "$db_port" ] || [ ! -x "$supabase_bin" ]; then
  echo "Unable to resolve the project-owned local Supabase configuration." >&2
  exit 1
fi

status_env=$("$node_exec" "$supabase_bin" status -o env)
api_url=$(printf '%s\n' "$status_env" | sed -n 's/^API_URL="\{0,1\}\([^" ]*\)"\{0,1\}$/\1/p')
db_url=$(printf '%s\n' "$status_env" | sed -n 's/^DB_URL="\{0,1\}\([^" ]*\)"\{0,1\}$/\1/p')
inbucket_url=$(printf '%s\n' "$status_env" | sed -n 's/^INBUCKET_URL="\{0,1\}\([^" ]*\)"\{0,1\}$/\1/p')
storage_url=$(printf '%s\n' "$status_env" | sed -n 's/^STORAGE_S3_URL="\{0,1\}\([^" ]*\)"\{0,1\}$/\1/p')

case "$api_url" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "Refusing non-loopback Supabase API target." >&2; exit 1 ;;
esac
case "$db_url" in
  postgresql://*@127.0.0.1:"$db_port"/*|postgres://*@127.0.0.1:"$db_port"/*|postgresql://*@localhost:"$db_port"/*|postgres://*@localhost:"$db_port"/*) ;;
  *) echo "Refusing a database target that is not the configured local port." >&2; exit 1 ;;
esac
case "$inbucket_url" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "Refusing non-loopback captured-mail target." >&2; exit 1 ;;
esac
case "$storage_url" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "Refusing non-loopback Storage target." >&2; exit 1 ;;
esac

resolve_db_container() {
  $docker_bin ps --format '{{.Names}}|{{.Ports}}' |
    awk -F '|' -v port="$db_port" '$1 ~ /^supabase_db_/ && $2 ~ (":" port "->5432/tcp") { print $1 }'
}

db_container=$(resolve_db_container)
if [ "$(printf '%s\n' "$db_container" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ] || [ "$db_container" != "supabase_db_$project_id" ]; then
  echo "Refusing reset: the configured local database container was not resolved uniquely." >&2
  exit 1
fi

echo "Resetting disposable local Supabase project '$project_id' on 127.0.0.1:$db_port..."
"$node_exec" "$supabase_bin" db reset --local --no-seed

db_container=$(resolve_db_container)
if [ "$db_container" != "supabase_db_$project_id" ]; then
  echo "Local database container changed unexpectedly after reset." >&2
  exit 1
fi

run_sql() {
  sql_file=$1
  echo "Running $sql_file..."
  $docker_bin exec -i "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres < "$sql_file"
}

run_sql supabase/tests/team_directory_page.sql
run_sql supabase/tests/document_upload_commands.sql
run_sql supabase/tests/trash_logical_expiry_and_shared_intake.sql
run_sql scripts/acceptance/seed.sql
"$node_exec" scripts/acceptance/seed-storage.mjs

echo "Disposable Team/upload fixtures, browser seed, and private Storage source passed."
