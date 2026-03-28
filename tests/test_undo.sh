#!/usr/bin/env bash
# tests/test_undo.sh — Tests for g undo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
source "${SCRIPT_DIR}/../lib/core.sh"
source "${SCRIPT_DIR}/../lib/undo.sh"

echo "Testing: g undo"

setup_repo

# Make a commit to undo
echo "hello" > file1.txt
git add file1.txt
git commit --quiet -m "feat: add file1"

HASH_BEFORE=$(git rev-parse HEAD)

# ─── undo commit --soft ──────────────────────────────────────────────────────
echo "y" | undo_commit --soft 2>/dev/null || true
assert_eq "soft undo: HEAD moved back" \
  "1" "$(git rev-list --count HEAD..${HASH_BEFORE} 2>/dev/null || echo 0)"

CURRENT_HEAD=$(git rev-parse HEAD)
assert_not_contains "soft undo: HEAD changed" "$HASH_BEFORE" "$CURRENT_HEAD"

# file1.txt should still be staged
staged=$(git diff --cached --name-only)
assert_contains "soft undo: file is still staged" "file1.txt" "$staged"

# Recommit for next test
git commit --quiet -m "feat: re-add file1"

# ─── undo commit (mixed) ─────────────────────────────────────────────────────
echo "y" | undo_commit 2>/dev/null || true
STAGED=$(git diff --cached --name-only)
# Use git status --porcelain to catch both modified-tracked and untracked files.
# After mixed reset to an empty parent commit, file1.txt becomes untracked
# (not in parent's tree), so git diff --name-only misses it.
WORKING=$(git status --porcelain | awk '{print $NF}')
assert_eq "mixed undo: nothing staged" "" "$STAGED"
assert_contains "mixed undo: file is in working tree" "file1.txt" "$WORKING"

# Restage and recommit
git add file1.txt
git commit --quiet -m "feat: re-add file1 again"

# ─── undo file ───────────────────────────────────────────────────────────────
echo "modified" > file1.txt
assert_exits_ok "undo file: file is dirty" is_dirty

echo "y" | undo_file "file1.txt" 2>/dev/null || true
CONTENT=$(cat file1.txt 2>/dev/null || echo "")
assert_eq "undo file: file restored to committed content" "hello" "$CONTENT"

# ─── undo_all_unstaged ────────────────────────────────────────────────────────
echo "dirty" > file1.txt
echo "new" > file2.txt
git add file2.txt  # stage file2
# Only file1 is unstaged

echo "y" | undo_all_unstaged 2>/dev/null || true
CONTENT=$(cat file1.txt 2>/dev/null || echo "")
assert_eq "undo all unstaged: file1 restored" "hello" "$CONTENT"
# file2 should remain staged
STAGED=$(git diff --cached --name-only)
assert_contains "undo all unstaged: staged files untouched" "file2.txt" "$STAGED"

teardown_repo

print_summary "g undo"
