#!/usr/bin/env bash
# tests/test_core.sh — Tests for lib/core.sh utilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
source "${SCRIPT_DIR}/../lib/core.sh"

echo "Testing: core.sh"

# ─── truncate_str ─────────────────────────────────────────────────────────────
assert_eq "truncate_str: short string unchanged" \
  "hello" "$(truncate_str "hello" 10)"

assert_eq "truncate_str: long string truncated" \
  "hello w..." "$(truncate_str "hello world foo bar" 10)"

assert_eq "truncate_str: exact length unchanged" \
  "hello" "$(truncate_str "hello" 5)"

# ─── has_cmd ─────────────────────────────────────────────────────────────────
assert_exits_ok "has_cmd: git exists" has_cmd git
assert_fails "has_cmd: nonexistent returns false" has_cmd __g_nonexistent_cmd_xyz__

# ─── require_git_repo: outside repo ──────────────────────────────────────────
OLD_DIR=$(pwd)
cd /tmp
assert_fails "require_git_repo: fails outside repo" require_git_repo
cd "$OLD_DIR"

# ─── current_branch / default_branch inside a repo ───────────────────────────
setup_repo

assert_eq "current_branch: returns branch name" \
  "$(git symbolic-ref --short HEAD)" "$(current_branch)"

assert_exits_ok "require_git_repo: passes inside repo" require_git_repo

assert_exits_ok "require_git_repo_with_commits: passes with commits" require_git_repo_with_commits

# ─── is_dirty / has_staged ───────────────────────────────────────────────────
assert_fails "is_dirty: clean repo is not dirty" is_dirty

echo "test content" > testfile.txt
git add testfile.txt

assert_exits_ok "is_dirty: repo with staged file is dirty" is_dirty
assert_exits_ok "has_staged: staged file detected" has_staged

git commit --quiet -m "test: add testfile"
assert_fails "is_dirty: clean after commit" is_dirty
assert_fails "has_staged: nothing staged after commit" has_staged

# ─── default_branch ──────────────────────────────────────────────────────────
default=$(default_branch)
assert_contains "default_branch: returns main or master" \
  "$default" "main master" || true  # contains check on space-separated list

teardown_repo

print_summary "core.sh"
