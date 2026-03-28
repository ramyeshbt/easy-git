#!/usr/bin/env bash
# lib/fixup.sh — g fixup: Create a fixup commit targeting an older commit, then autosquash
# Common code-review workflow: reviewer asks for change → fixup → autosquash before merge
# Usage: g fixup [<hash>] [--squash] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_fixup() {
  require_git_repo_with_commits

  case "${1:-}" in
    -h|--help) usage_fixup; return 0 ;;
  esac

  local target=""
  local autosquash=0
  local squash_mode=0  # --squash keeps message editable, --fixup auto-drops

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --squash)     squash_mode=1; shift ;;
      --autosquash) autosquash=1; shift ;;
      -*)           die "Unknown flag: $1. Use 'g fixup --help'" ;;
      *)            target="$1"; shift ;;
    esac
  done

  # Must have staged changes to create a fixup
  if ! has_staged; then
    if is_dirty; then
      warn "Nothing is staged for the fixup."
      if confirm "Stage all changes now?"; then
        run_cmd git add -A
      else
        hint "Use 'git add <file>' to stage the fix, then run 'g fixup' again."
        return 1
      fi
    else
      warn "Nothing to fix up — working tree is clean."
      return 0
    fi
  fi

  # If no target, pick from recent commits interactively
  if [ -z "$target" ]; then
    local commits=()
    while IFS= read -r line; do
      commits+=("$line")
    done < <(git log --oneline -20)

    [ "${#commits[@]}" -eq 0 ] && die "No commits to fix up."

    header "Pick commit to fix up:"
    local selected
    selected=$(fuzzy_select "Fix up which commit?" "${commits[@]}")
    [ -z "$selected" ] && return 1
    target=$(echo "$selected" | awk '{print $1}')
  fi

  # Validate hash
  if ! git rev-parse --verify "${target}^{commit}" &>/dev/null; then
    die "Not a valid commit: '$target'"
  fi

  local hash msg
  hash=$(git rev-parse --short "$target")
  msg=$(git log -1 --pretty=format:"%s" "$target")

  echo ""
  echo -e "${BOLD}Creating fixup for:${RESET}"
  echo -e "  ${CYAN}${hash}${RESET}  ${msg}"
  echo ""

  # Show the staged diff
  echo -e "${BOLD}Staged changes:${RESET}"
  git diff --cached --stat | sed 's/^/  /'
  echo ""

  if [ "$squash_mode" = "1" ]; then
    run_cmd git commit --squash "$target"
    success "Squash commit created. It will be merged into '${hash}' during rebase."
  else
    run_cmd git commit --fixup "$target"
    success "Fixup commit created. It will be auto-squashed into '${hash}' during rebase."
  fi

  # Offer to autosquash now
  if [ "$autosquash" = "1" ]; then
    _run_autosquash "$target"
  else
    hint "Run 'g fixup --autosquash' or:"
    hint "  git rebase -i --autosquash ${hash}~1"
    hint "to automatically apply the fix."
  fi
}

_run_autosquash() {
  local target="$1"
  local hash
  hash=$(git rev-parse --short "$target")

  echo ""
  warn "Autosquash will rewrite history by merging fixup commits into their targets."
  warn "Only do this on commits NOT yet pushed, or on a private branch."
  echo ""

  confirm "Run autosquash now (git rebase --autosquash)?" || return 1

  # Use GIT_SEQUENCE_EDITOR=true to skip the interactive editor
  GIT_SEQUENCE_EDITOR="true" run_cmd git rebase -i --autosquash "${target}~1"
  success "Autosquash complete."
  hint "Run 'g push --force' if this branch is already on the remote."
}

usage_fixup() {
  cat <<EOF
${BOLD}g fixup${RESET} — Create a fixup commit for a previous commit (code review workflow)

${BOLD}USAGE${RESET}
  g fixup                    # Stage changes first, then pick commit interactively
  g fixup <hash>             # Attach staged changes as fixup to specific commit
  g fixup --autosquash       # Create fixup AND immediately autosquash into target
  g fixup --squash           # Like fixup but keeps commit message editable

${BOLD}TYPICAL CODE REVIEW WORKFLOW${RESET}
  1. PR reviewer requests change in commit abc123
  2. Make the change
  3. g fixup abc123          # Creates "fixup! <original message>" commit
  4. g fixup --autosquash    # OR: squash it in before pushing
  5. g push --force          # Push the cleaned-up history

${BOLD}FLAGS${RESET}
  --squash      Create a squash commit (message editable on rebase)
  --autosquash  Create fixup AND run autosquash rebase immediately
  -h, --help    Show this help

${BOLD}SECURITY NOTE${RESET}
  --autosquash rewrites history. Only use on private/unshared branches.
  After autosquash, you'll need 'g push --force'.
EOF
}
