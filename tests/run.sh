#!/usr/bin/env bash
# Runs every query in queries/ on a throwaway database with planted problems and compares with expected.txt.
set -euo pipefail
out="$(mktemp)"
cd "$(dirname "$0")/.."
dropdb --if-exists checklist_test >/dev/null 2>&1; createdb checklist_test
psql -X -q -v ON_ERROR_STOP=1 -d checklist_test -f tests/setup.sql >/dev/null 2>&1
for f in queries/*.sql; do echo "== $(basename "$f")"; psql -X -q -v ON_ERROR_STOP=1 -d checklist_test -At -F '|' -f "$f"; done > "$out"
dropdb checklist_test
if diff "$out" tests/expected.txt; then echo "PASS: every query returns the planted rows and nothing else"; else echo "FAIL"; exit 1; fi
