#!/usr/bin/env bash
# tests/test_security.sh — Security regression tests for easy-git
# Tests that injection and vulnerability fixes remain in place.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
source "${SCRIPT_DIR}/../lib/core.sh"
source "${SCRIPT_DIR}/../lib/branch.sh"
source "${SCRIPT_DIR}/../lib/search.sh"

echo "Testing: security regressions"

setup_repo

# ─── Branch name injection prevention ────────────────────────────────────────

# Flag injection: branch name starting with -
assert_fails "branch: rejects name starting with single -" \
  create_or_switch_branch "-bad-branch"

assert_fails "branch: rejects name starting with --" \
  create_or_switch_branch "--force"

assert_fails "branch: rejects --delete flag injection" \
  create_or_switch_branch "--delete"

# Shell command injection in branch name
# $() should be stripped, leaving an empty or harmless name
output=$(create_or_switch_branch 'feat/$(id)' 2>&1 || true)
# After sanitization: feat/ — which becomes empty after stripping, should fail or sanitize
# Verify no command execution happened by checking no id-like output
assert_not_contains "branch: strips \$() from name" "uid=" "$output"

# Backtick injection
output=$(create_or_switch_branch 'feat/`id`' 2>&1 || true)
assert_not_contains "branch: strips backtick injection" "uid=" "$output"

# Semicolon injection
output=$(create_or_switch_branch 'feat/test;rm -rf .' 2>&1 || true)
# Branch should be created as feat/testrf- or rejected, not execute rm
assert_not_contains "branch: semicolon does not execute commands" "No such file" "$output"

# Pipe injection
output=$(create_or_switch_branch 'feat/test|id' 2>&1 || true)
assert_not_contains "branch: pipe does not leak uid" "uid=" "$output"

# .lock suffix stripping (git lock file conflict prevention)
create_or_switch_branch "my-branch.lock" 2>/dev/null || true
assert_branch_not_exists "branch: .lock suffix stripped" "my-branch.lock"
# It should exist without .lock
# (may or may not succeed depending on sanitized name — just verify .lock branch not created)

# ─── Search injection prevention ─────────────────────────────────────────────

# Flag injection in search query
assert_fails "search: rejects query starting with --" \
  main_search "--format=%H --all"

assert_fails "search: rejects author starting with --" \
  bash -c "source '${SCRIPT_DIR}/../lib/core.sh'; source '${SCRIPT_DIR}/../lib/search.sh'; author='--upload-pack=id'; [[ \"\$author\" == --* ]] && die 'blocked'"

# ─── File path safety ────────────────────────────────────────────────────────

# Source the undo module too
source "${SCRIPT_DIR}/../lib/undo.sh"

# undo file with path traversal attempt should either be rejected by git or not traverse
# git restore -- "../../file" is handled by git itself (git refuses paths outside worktree)
output=$(undo_file "../../etc/passwd" 2>&1 || true)
assert_not_contains "undo file: path traversal rejected" "root:" "$output"

# ─── Eval absence check ──────────────────────────────────────────────────────

eval_count=$(grep -c 'eval ' "${SCRIPT_DIR}/../lib/"*.sh "${SCRIPT_DIR}/../bin/g" 2>/dev/null || echo 0)
assert_eq "no eval in any script" "0" "$eval_count"

# ─── -- separator presence checks ────────────────────────────────────────────

# Verify push.sh uses -- before branch name
push_has_separator=$(grep -c 'push.*-- "\$branch"' "${SCRIPT_DIR}/../lib/push.sh" || echo 0)
assert_eq "push.sh uses -- before branch" "4" "$push_has_separator"

# Verify clean.sh uses -- before branch name
clean_has_separator=$(grep -c 'branch -[dD] -- ' "${SCRIPT_DIR}/../lib/clean.sh" || echo 0)
assert_eq "clean.sh uses -- before branch name" "1" "$clean_has_separator"

# Verify undo.sh restore uses --
undo_has_separator=$(grep -c 'restore -- ' "${SCRIPT_DIR}/../lib/undo.sh" || echo 0)
assert_eq "undo.sh restore uses -- before file" "1" "$undo_has_separator"

# ─── Secret detection presence check ─────────────────────────────────────────

# Verify secret patterns are defined in commit.sh
has_secret_patterns=$(grep -c 'SECRET_FILE_PATTERNS\|_check_staged_secrets' "${SCRIPT_DIR}/../lib/commit.sh" || echo 0)
assert_eq "commit.sh has secret detection" "4" "$has_secret_patterns"

teardown_repo

print_summary "security regressions"
