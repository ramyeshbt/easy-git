#!/usr/bin/env bash
# tests/test_clean.sh — Tests for g clean

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
source "${SCRIPT_DIR}/../lib/core.sh"
source "${SCRIPT_DIR}/../lib/clean.sh"

echo "Testing: g clean"

setup_repo

DEFAULT=$(default_branch)

# ─── clean: dry-run with no stale branches ────────────────────────────────────
output=$(main_clean --dry-run 2>&1 || true)
assert_contains "clean --dry-run: reports no stale branches" "No stale branches" "$output"

# ─── clean: merged branch is detected ────────────────────────────────────────
git checkout -b "merged-feature" --quiet
echo "content" > merged.txt
git add merged.txt
git commit --quiet -m "feat: merged feature"

git checkout "$DEFAULT" --quiet
git merge "merged-feature" --quiet --no-ff -m "merge: merged-feature"

output=$(main_clean --dry-run 2>&1 || true)
assert_contains "clean --dry-run: detects merged-feature" "merged-feature" "$output"

# ─── clean: actually deletes merged branch ────────────────────────────────────
echo "y" | main_clean 2>/dev/null || true
assert_branch_not_exists "clean: deleted merged-feature" "merged-feature"

# ─── clean: does not delete default branch ────────────────────────────────────
output=$(main_clean --dry-run 2>&1 || true)
assert_not_contains "clean: does not touch default branch" "$DEFAULT" "$output"

teardown_repo

print_summary "g clean"
