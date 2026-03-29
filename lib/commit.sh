#!/usr/bin/env bash
# lib/commit.sh — g commit: Smart interactive commit with conventional format
# Usage: g commit [message] [-a] [--amend] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

# Conventional commit types with descriptions
COMMIT_TYPES=(
  "feat:     A new feature"
  "fix:      A bug fix"
  "docs:     Documentation changes only"
  "style:    Formatting, missing semicolons (no logic change)"
  "refactor: Code refactored (no feature/fix)"
  "test:     Adding or fixing tests"
  "chore:    Build process, dependency updates, tooling"
  "perf:     Performance improvement"
  "ci:       CI/CD configuration changes"
  "revert:   Revert a previous commit"
)

# Dangerous file/content patterns that suggest secrets being committed
SECRET_FILE_PATTERNS="\.env$|\.env\.|\.pem$|\.key$|_rsa$|_dsa$|_ecdsa$|_ed25519$|credentials|secrets\.|\.p12$|\.pfx$|\.jks$|id_rsa|id_dsa|\.netrc$|\.aws/credentials|\.docker/config\.json|\.kube/config|\.npmrc|\.env\.local|\.vault-pass|terraform\.tfvars"
SECRET_CONTENT_PATTERNS="AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36}|gl[oa]_[A-Za-z0-9_]{20,}|npm_[A-Za-z0-9]{36}|pypi-AgE[A-Za-z0-9_\-]{50,}|-----BEGIN (RSA|DSA|EC|OPENSSH|PRIVATE) KEY|password\s*=\s*['\"][^'\"]{6,}['\"]|api_?key\s*=\s*\S{16,}|(postgres|mysql|mongodb)://[^@\s]+:[^@\s]+@|eyJ[A-Za-z0-9_\-=]{10,}\.eyJ[A-Za-z0-9_\-=]"

_check_staged_secrets() {
  local risky_files=()

  # Check filenames
  while IFS= read -r staged_file; do
    if echo "$staged_file" | grep -qiE "$SECRET_FILE_PATTERNS"; then
      risky_files+=("$staged_file")
    fi
  done < <(git diff --cached --name-only)

  if [ "${#risky_files[@]}" -gt 0 ]; then
    echo ""
    echo -e "${RED}${BOLD}⚠  SECRET FILE WARNING${RESET}"
    echo -e "${RED}  The following staged files may contain secrets:${RESET}"
    for f in "${risky_files[@]}"; do
      echo -e "    ${RED}✗${RESET}  $f"
    done
    echo ""
    if ! confirm "These files look like they may contain credentials. Commit anyway?"; then
      warn "Commit cancelled. Consider adding these files to .gitignore."
      return 1
    fi
  fi

  # Check content for secret patterns (only if grep -P is available — GNU grep)
  if git diff --cached --unified=0 2>/dev/null | grep -qP "$SECRET_CONTENT_PATTERNS" 2>/dev/null; then
    echo ""
    echo -e "${RED}${BOLD}⚠  SECRET CONTENT WARNING${RESET}"
    echo -e "${RED}  Staged diff appears to contain credential patterns (API keys, tokens, private keys).${RESET}"
    echo ""
    git diff --cached --unified=0 | grep -P "$SECRET_CONTENT_PATTERNS" 2>/dev/null | head -5 | sed 's/^/    /'
    echo ""
    if ! confirm "Staged content looks like it may contain secrets. Commit anyway?"; then
      warn "Commit cancelled. Remove secrets and use environment variables instead."
      return 1
    fi
  fi
}

main_commit() {
  require_git_repo

  local amend=0
  local stage_all=0
  local message=""

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage_commit; return 0 ;;
      --amend)   amend=1; shift ;;
      -a|--all)  stage_all=1; shift ;;
      -*)        die "Unknown flag: $1. Use 'g commit --help'" ;;
      *)         message="$1"; shift ;;
    esac
  done

  # Stage all if -a flag or if nothing is staged and there are changes
  if [ "$stage_all" = "1" ]; then
    info "Staging all tracked changes..."
    run_cmd git add -u
  fi

  if ! has_staged && [ "$amend" = "0" ]; then
    # Nothing staged — offer to stage everything
    if is_dirty; then
      warn "Nothing is staged."
      if confirm "Stage all changes now?"; then
        run_cmd git add -A
      else
        hint "Use 'git add <file>' to stage specific files, then run 'g commit' again."
        return 1
      fi
    else
      warn "Nothing to commit — working tree is clean."
      return 0
    fi
  fi

  # Show what's staged
  header "Staged changes:"
  git diff --cached --stat | sed 's/^/  /'
  echo ""

  # Security: warn about staged secret-like files before committing
  _check_staged_secrets

  # If message not provided, build it interactively
  # Must NOT call inside $() — build_commit_message displays the type list
  # to stdout, and $() would capture that display instead of showing it.
  if [ -z "$message" ]; then
    _COMMIT_MSG=""
    build_commit_message
    message="$_COMMIT_MSG"
    [ -z "$message" ] && return 1
  fi

  # Commit
  if [ "$amend" = "1" ]; then
    run_cmd git commit --amend -m "$message"
  else
    run_cmd git commit -m "$message"
  fi

  # Show result
  local hash branch
  hash=$(git rev-parse --short HEAD)
  branch=$(current_branch)
  success "Committed ${BOLD}[$hash]${RESET} on ${CYAN}$branch${RESET}"
  echo -e "  ${DIM}$message${RESET}"
  hint "Run 'g push' to push your changes."
}

# Module-level global — set by build_commit_message, read by main_commit.
# Must not be called inside $() — all display goes to stdout.
_COMMIT_MSG=""

build_commit_message() {
  _COMMIT_MSG=""
  local type scope subject body breaking

  # Step 1: Choose commit type
  echo -e "${BOLD}Select commit type:${RESET}"
  local type_keys=()
  local i
  for i in "${!COMMIT_TYPES[@]}"; do
    local entry="${COMMIT_TYPES[$i]}"
    local key="${entry%%:*}"
    type_keys+=("$key")
    printf "  ${CYAN}%2d${RESET}) %s\n" "$((i+1))" "$entry"
  done

  local choice
  printf "%b" "\n${YELLOW}?${RESET} Type [1-${#COMMIT_TYPES[@]}]: "
  read -r choice </dev/tty

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#COMMIT_TYPES[@]}" ]; then
    type="${type_keys[$((choice-1))]}"
  else
    type=$(prompt_input "Type (feat/fix/docs/etc)")
    [ -z "$type" ] && { warn "Commit type is required."; return 1; }
  fi

  # Step 2: Optional scope
  scope=$(prompt_input "Scope (optional, e.g. auth, api, ui)" "")

  # Step 3: Subject line
  subject=$(prompt_input "Subject (short description)")
  if [ -z "$subject" ]; then
    warn "Commit subject is required."
    return 1
  fi
  # Lowercase first letter, remove trailing period
  # NOTE: ${var,} is bash 4.0+ only — use tr for bash 3.2 (macOS) compatibility
  subject="$(echo "${subject:0:1}" | tr '[:upper:]' '[:lower:]')${subject:1}"
  subject="${subject%.}"

  # Step 4: Breaking change?
  local breaking_flag=""
  if confirm "Is this a breaking change?"; then
    breaking_flag="!"
    echo -e "${YELLOW}?${RESET} Describe the breaking change:"
    read -r breaking </dev/tty
  fi

  # Assemble the commit message header
  local header
  if [ -n "$scope" ]; then
    header="${type}${breaking_flag}(${scope}): ${subject}"
  else
    header="${type}${breaking_flag}: ${subject}"
  fi

  # Step 5: Optional body
  echo -e "\n${CYAN}?${RESET} Body (optional, press Enter to skip, Ctrl+D when done):"
  local body_lines=()
  while IFS= read -r line </dev/tty; do
    [ -z "$line" ] && break
    body_lines+=("$line")
  done 2>/dev/null || true

  # Assemble full message
  local full_message="$header"
  if [ "${#body_lines[@]}" -gt 0 ]; then
    full_message="${full_message}"$'\n\n'
    local l
    for l in "${body_lines[@]}"; do
      full_message="${full_message}${l}"$'\n'
    done
  fi
  if [ -n "${breaking:-}" ]; then
    full_message="${full_message}"$'\n'"BREAKING CHANGE: ${breaking}"
  fi

  echo ""
  echo -e "${DIM}Commit message:${RESET}"
  echo "$full_message" | sed 's/^/  /'
  echo ""

  if confirm "Use this message?"; then
    _COMMIT_MSG="$full_message"
  else
    warn "Commit cancelled."
    return 1
  fi
}

usage_commit() {
  cat <<EOF
${BOLD}g commit${RESET} — Interactive conventional commit

${BOLD}USAGE${RESET}
  g commit [message] [flags]

${BOLD}FLAGS${RESET}
  -a, --all     Stage all tracked changes before committing
  --amend       Amend the last commit
  -h, --help    Show this help

${BOLD}EXAMPLES${RESET}
  g commit                          # Interactive commit builder
  g commit "fix: correct typo"      # Quick commit with message
  g commit -a                       # Stage all tracked + commit interactively
  g commit --amend                  # Amend last commit message

${BOLD}CONVENTIONAL COMMIT TYPES${RESET}
  feat, fix, docs, style, refactor, test, chore, perf, ci, revert
EOF
}
