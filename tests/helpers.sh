#!/usr/bin/env bash
# tests/helpers.sh — Test utilities for easy-git tests

PASS=0
FAIL=0
TEST_DIR=""

# ─── Test lifecycle ───────────────────────────────────────────────────────────

# Create a fresh temporary git repo for testing
setup_repo() {
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR" || return 1
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test User"
  git config commit.gpgsign false
  # Initial commit so HEAD exists
  git commit --allow-empty -m "chore: initial commit" --quiet
}

# Clean up temp repo
teardown_repo() {
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
  TEST_DIR=""
}

# ─── Assertion helpers ────────────────────────────────────────────────────────

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    _pass "$label"
  else
    _fail "$label" "Expected: '$expected', Got: '$actual'"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -q "$needle"; then
    _pass "$label"
  else
    _fail "$label" "Expected '$haystack' to contain '$needle'"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if ! echo "$haystack" | grep -q "$needle"; then
    _pass "$label"
  else
    _fail "$label" "Expected '$haystack' NOT to contain '$needle'"
  fi
}

assert_exits_ok() {
  local label="$1"
  shift
  if "$@" &>/dev/null; then
    _pass "$label"
  else
    _fail "$label" "Command failed: $*"
  fi
}

assert_fails() {
  local label="$1"
  shift
  if ! "$@" &>/dev/null; then
    _pass "$label"
  else
    _fail "$label" "Expected command to fail: $*"
  fi
}

assert_file_exists() {
  local label="$1" filepath="$2"
  if [ -f "$filepath" ]; then
    _pass "$label"
  else
    _fail "$label" "File not found: $filepath"
  fi
}

assert_branch_exists() {
  local label="$1" branch="$2"
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    _pass "$label"
  else
    _fail "$label" "Branch '$branch' does not exist"
  fi
}

assert_branch_not_exists() {
  local label="$1" branch="$2"
  if ! git show-ref --verify --quiet "refs/heads/$branch"; then
    _pass "$label"
  else
    _fail "$label" "Branch '$branch' should not exist"
  fi
}

# ─── Internal helpers ────────────────────────────────────────────────────────

_pass() {
  local label="$1"
  PASS=$((PASS + 1))
  if [ "${VERBOSE:-0}" = "1" ]; then
    echo "  ✓ $label"
  fi
}

_fail() {
  local label="$1" reason="$2"
  FAIL=$((FAIL + 1))
  echo "  ✗ FAIL: $label"
  echo "    → $reason"
}

# Print test suite summary and exit with correct code
print_summary() {
  local suite="${1:-Tests}"
  local total=$((PASS + FAIL))
  echo ""
  echo "─────────────────────────────────"
  echo "${suite}: ${total} tests — ${PASS} passed, ${FAIL} failed"
  echo "─────────────────────────────────"
  [ "$FAIL" -eq 0 ]
}
