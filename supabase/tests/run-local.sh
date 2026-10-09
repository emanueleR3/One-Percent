#!/bin/zsh
# Runs the migration and its behaviour tests on a throwaway Postgres in Docker (nothing touches
# your Supabase project). Needs Docker and a postgres image; set PG_IMAGE to use another one.
set -euo pipefail

here="${0:A:h}"
image="${PG_IMAGE:-postgres:17}"
name="one-percent-sync-test-$$"

cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true }
trap cleanup EXIT

docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=test "$image" >/dev/null
for _ in {1..60}; do
    docker exec "$name" pg_isready -U postgres >/dev/null 2>&1 && break
    sleep 1
done
sleep 1

psql() { docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 -q "$@" }

echo "== stubs";               psql < "$here/local-stubs.sql"
echo "== migration (1st run)"; psql < "$here/../migrations/"*.sql
echo "== migration (2nd run, must be a no-op)"; psql < "$here/../migrations/"*.sql
echo "== tests";               psql < "$here/schema_test.sql"
