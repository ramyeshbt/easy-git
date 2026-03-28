#!/usr/bin/env bash
# lib/revert.sh — g revert: Safely revert a commit (creates a new revert commit)
# Unlike g undo, revert is safe on shared/public branches — it doesn't rewrite history.
# Usage: g revert [<hash>] [--no-commit] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_revert() {
  require_git_repo_with_commits

  local no_commit=0
  local target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)    usage_revert; return 0 ;;
      -n|--no-commit) no_commit=1; shift ;;
      -*)           die "Unknown flag: $1. Use 'g revert --help'" ;;
      *)            target="$1"; shift ;;
    esac
  done

  # If no target given, pick interactively from recent commits
  if [ -z "$target" ]; then
    target=$(_pick_commit "Select commit to revert")
    [ -z "$target" ] && return 1
  fi

  # Validate the hash
  if ! git rev-parse --verify "${target}^{commit}" &>/dev/null; then
    die "Not a valid commit: '$target'"
  fi

  local hash msg author date
  hash=$(git rev-parse --short "$target")
  msg=$(git log -1 --pretty=format:"%s" "$target")
  author=$(git log -1 --pretty=format:"%an" "$target")
  date=$(git log -1 --pretty=format:"%ar" "$target")

  # Show what will be reverted
  echo ""
  echo -e "${BOLD}Commit to revert:${RESET}"
  echo -e "  ${CYAN}${hash}${RESET}  ${msg}"
  echo -e "  ${DIM}by ${author}, ${date}${RESET}"
  echo ""
  echo -e "${BOLD}This will:${RESET}"
  echo -e "  Create a NEW commit that undoes the changes from ${CYAN}${hash}${RESET}"
  echo -e "  ${GREEN}✓ Safe on shared branches — does NOT rewrite history${RESET}"
  echo ""

  confirm "Revert commit '${hash}'?" || return 1

  if [ "$no_commit" = "1" ]; then
    run_cmd git revert --no-commit "$target"
    success "Changes from '${hash}' staged for revert — review with 'g diff --staged', then 'g commit'."
  else
    run_cmd git revert --no-edit "$target"
    local new_hash
    new_hash=$(git rev-parse --short HEAD)
    success "Reverted ${CYAN}${hash}${RESET} — new commit: ${CYAN}${new_hash}${RESET}"
    hint "Run 'g push' to push the revert to remote."
  fi
}

_pick_commit() {
  local prompt="$1"
  local commits=()
  while IFS= read -r line; do
    commits+=("$line")
  done < <(git log --oneline -20)

  [ "${#commits[@]}" -eq 0 ] && { warn "No commits found."; return 1; }

  local selected
  selected=$(fuzzy_select "$prompt" "${commits[@]}")
  [ -z "$selected" ] && return 1

  # Extract the hash (first word)
  echo "$selected" | awk '{print $1}'
}

usage_revert() {
  cat <<EOF
${BOLD}g revert${RESET} — Safely undo a commit by creating a new revert commit

${BOLD}USAGE${RESET}
  g revert               # Pick from recent commits interactively
  g revert <hash>        # Revert a specific commit by hash

${BOLD}FLAGS${RESET}
  -n, --no-commit    Stage the revert without committing (lets you review first)
  -h, --help         Show this help

${BOLD}WHEN TO USE g revert vs g undo${RESET}
  g revert   → Safe on shared/public branches. Creates a new commit.
               Use when the bad commit is already pushed and others may have it.
  g undo     → Rewrites history (reset). Only safe on your own private branches.
               Use when the bad commit is NOT yet pushed.

${BOLD}EXAMPLES${RESET}
  g revert                    # Interactive — pick from last 20 commits
  g revert abc1234            # Revert a specific commit
  g revert --no-commit abc123 # Stage revert changes to review before committing
EOF
}
