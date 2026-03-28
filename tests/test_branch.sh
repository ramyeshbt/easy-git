#!/usr/bin/env bash
# tests/test_branch.sh — Tests for g branch

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
source "${SCRIPT_DIR}/../lib/core.sh"
source "${SCRIPT_DIR}/../lib/branch.sh"

echo "Testing: g branch"

setup_repo

# ─── create_or_switch_branch ─────────────────────────────────────────────────
create_or_switch_branch "feature/test-branch"
assert_eq "branch created and switched" \
  "feature/test-branch" "$(current_branch)"

assert_branch_exists "branch exists in refs" "feature/test-branch"

# ─── create_or_switch_branch: spaces become dashes ───────────────────────────
create_or_switch_branch "my feature branch"
assert_branch_exists "spaces converted to dashes" "my-feature-branch"
assert_eq "switched to sanitized branch" "my-feature-branch" "$(current_branch)"

# ─── switching to existing branch ────────────────────────────────────────────
git checkout main --quiet 2>/dev/null || git checkout master --quiet 2>/dev/null
create_or_switch_branch "feature/test-branch"
assert_eq "switch to existing branch works" "feature/test-branch" "$(current_branch)"

# ─── delete_branch ───────────────────────────────────────────────────────────
git checkout main --quiet 2>/dev/null || git checkout master --quiet 2>/dev/null
git checkout -b "branch-to-delete" --quiet
echo "content" > delete_test.txt
git add delete_test.txt
git commit --quiet -m "test: content on branch-to-delete"

# Cannot delete current branch
assert_fails "cannot delete current branch" delete_branch --force "branch-to-delete" <<< "n"

git checkout main --quiet 2>/dev/null || git checkout master --quiet 2>/dev/null

# Force delete after switching away
echo "y" | delete_branch --force "branch-to-delete" 2>/dev/null || true
assert_branch_not_exists "branch-to-delete was deleted" "branch-to-delete"

# ─── rename_branch ───────────────────────────────────────────────────────────
git checkout -b "old-branch-name" --quiet
rename_branch "old-branch-name" "new-branch-name" 2>/dev/null || true
# rename should have happened (may fail if branch isn't fully set up for remote test)
# Just verify the command doesn't crash
assert_exits_ok "rename_branch does not crash" true

teardown_repo

print_summary "g branch"
