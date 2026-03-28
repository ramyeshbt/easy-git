#!/usr/bin/env bash
# tests/run_tests.sh — Discover and run all test_*.sh files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE="${VERBOSE:-0}"
export VERBOSE

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()

echo ""
echo "╔══════════════════════════════════════╗"
echo "║       easy-git Test Suite            ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Run each test file
for test_file in "${SCRIPT_DIR}"/test_*.sh; do
  [ -f "$test_file" ] || continue
  suite_name=$(basename "$test_file" .sh)

  echo "▶  Running: ${suite_name}"

  # Capture output and exit code — set +e prevents set -euo pipefail from
  # killing the runner when a test suite exits with non-zero
  set +e
  output=$(bash "$test_file" 2>&1)
  exit_code=$?
  set -e

  echo "$output"

  # Parse pass/fail counts from summary line
  pass=$(echo "$output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || echo 0)
  fail=$(echo "$output" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo 0)

  TOTAL_PASS=$((TOTAL_PASS + pass))
  TOTAL_FAIL=$((TOTAL_FAIL + fail))

  if [ "$exit_code" -ne 0 ] || [ "${fail:-0}" -gt 0 ]; then
    FAILED_SUITES+=("$suite_name")
  fi

  echo ""
done

# ─── Syntax check ────────────────────────────────────────────────────────────
echo "▶  Syntax check: bash -n"
SYNTAX_OK=1
for f in "${SCRIPT_DIR}/../bin/g" "${SCRIPT_DIR}/../lib/"*.sh; do
  if ! bash -n "$f" 2>/dev/null; then
    echo "  ✗ Syntax error in: $f"
    SYNTAX_OK=0
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
done
if [ "$SYNTAX_OK" = "1" ]; then
  echo "  ✓ All scripts pass syntax check"
fi
echo ""

# ─── Final summary ───────────────────────────────────────────────────────────
TOTAL=$((TOTAL_PASS + TOTAL_FAIL))
echo "════════════════════════════════════════"
echo "  Total: ${TOTAL} tests — ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed"

if [ "${#FAILED_SUITES[@]}" -gt 0 ]; then
  echo "  Failed suites:"
  for s in "${FAILED_SUITES[@]}"; do
    echo "    ✗ $s"
  done
  echo "════════════════════════════════════════"
  echo ""
  exit 1
else
  echo "  ✓ All tests passed!"
  echo "════════════════════════════════════════"
  echo ""
  exit 0
fi
