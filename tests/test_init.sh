#!/usr/bin/env bash
# tests/test_init.sh — Tests for g init (non-interactive parts only)
# Interactive wizard steps (prompt_input / read </dev/tty) cannot be tested
# without a real TTY, so we test the file-writing helpers directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
source "${SCRIPT_DIR}/../lib/core.sh"
source "${SCRIPT_DIR}/../lib/init.sh"

echo "Testing: g init"

# ─── Help / usage ─────────────────────────────────────────────────────────────
assert_exits_ok "g init --help exits cleanly" \
  main_init --help

output=$(main_init --help 2>&1 || true)
assert_contains "g init --help mentions USAGE" "USAGE" "$output"
assert_contains "g init --help mentions gitignore" ".gitignore" "$output"
assert_contains "g init --help mentions identity" "identity" "$output"

# ─── init registered in bin/g ─────────────────────────────────────────────────
assert_contains "init registered in bin/g dispatch" "main_init" \
  "$(cat "${SCRIPT_DIR}/../bin/g")"

# ─── _write_gitignore — all templates create .gitignore ──────────────────────
tmp_dir=$(mktemp -d)
cd "$tmp_dir" || exit 1

# Every template must create a .gitignore that contains .env (secret protection)
for tmpl in "Node.js" "Python" "Go" "Rust" "Java" "Ruby" "C/C++" "PHP" "Generic"; do
  rm -f .gitignore
  _write_gitignore "$tmpl"
  assert_exits_ok ".gitignore created for: $tmpl"   test -f .gitignore
  assert_contains ".gitignore/$tmpl has .env"        ".env"   "$(cat .gitignore)"
  assert_contains ".gitignore/$tmpl has *.pem"       "*.pem"  "$(cat .gitignore)"
  assert_contains ".gitignore/$tmpl has .DS_Store"   ".DS_Store" "$(cat .gitignore)"
done

# ─── Template-specific key entries ────────────────────────────────────────────
rm -f .gitignore
_write_gitignore "Node.js"
assert_contains "Node.js: node_modules"   "node_modules/" "$(cat .gitignore)"
assert_contains "Node.js: dist"           "dist/"         "$(cat .gitignore)"

rm -f .gitignore
_write_gitignore "Python"
assert_contains "Python: __pycache__"     "__pycache__/"  "$(cat .gitignore)"
assert_contains "Python: venv"            "venv/"         "$(cat .gitignore)"

rm -f .gitignore
_write_gitignore "Go"
assert_contains "Go: vendor"              "vendor/"       "$(cat .gitignore)"
assert_contains "Go: test binary"         "*.test"        "$(cat .gitignore)"

rm -f .gitignore
_write_gitignore "Rust"
assert_contains "Rust: target"            "/target/"      "$(cat .gitignore)"

rm -f .gitignore
_write_gitignore "Java"
assert_contains "Java: class files"       "*.class"       "$(cat .gitignore)"
assert_contains "Java: maven target"      "target/"       "$(cat .gitignore)"

rm -f .gitignore
_write_gitignore "Ruby"
assert_contains "Ruby: bundle"            ".bundle/"      "$(cat .gitignore)"

rm -f .gitignore
_write_gitignore "C/C++"
assert_contains "C/C++: object files"    "*.o"            "$(cat .gitignore)"
assert_contains "C/C++: static libs"     "*.a"            "$(cat .gitignore)"

rm -f .gitignore
_write_gitignore "PHP"
assert_contains "PHP: vendor"             "/vendor/"      "$(cat .gitignore)"

rm -f .gitignore
_write_gitignore "Generic"
assert_contains "Generic: build dir"      "build/"        "$(cat .gitignore)"

# ─── Unknown template falls back to Generic ───────────────────────────────────
rm -f .gitignore
_write_gitignore "UnknownLanguage"
assert_exits_ok "unknown template still creates .gitignore" test -f .gitignore
assert_contains "unknown template has .env" ".env" "$(cat .gitignore)"

# ─── Secrets section always appended ──────────────────────────────────────────
for tmpl in "Node.js" "Python" "Go"; do
  rm -f .gitignore
  _write_gitignore "$tmpl"
  assert_contains "$tmpl: private keys blocked"      "*_rsa"       "$(cat .gitignore)"
  assert_contains "$tmpl: terraform secrets blocked" "terraform.tfvars" "$(cat .gitignore)"
  assert_contains "$tmpl: aws credentials blocked"   ".aws/credentials" "$(cat .gitignore)"
done

# ─── Cleanup ──────────────────────────────────────────────────────────────────
cd /tmp
rm -rf "$tmp_dir"

print_summary "g init"
