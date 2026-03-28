#!/usr/bin/env bash
# lib/squash.sh — g squash: Squash WIP commits into clean commits before merging
# Usage: g squash [<count>] [--into <base>] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_squash() {
  require_git_repo_with_commits

  case "${1:-}" in
    -h|--help) usage_squash; return 0 ;;
  esac

  local count=""
  local base=""
  local method="count"  # "count" or "base"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --into|-b) shift; base="$1"; method="base"; shift ;;
      --all|-a)  method="base"; base=$(default_branch); shift ;;
      [0-9]*)    count="$1"; shift ;;
      *)         die "Unknown argument: $1. Use 'g squash --help'" ;;
    esac
  done

  local current
  current=$(current_branch)
  local default
  default=$(default_branch)

  if [ "$current" = "$default" ]; then
    die "You're on '$default'. Switch to a feature branch first."
  fi

  # Determine range
  if [ "$method" = "base" ]; then
    base="${base:-$default}"
    count=$(git rev-list --count "${base}..HEAD" 2>/dev/null || echo 0)
    if [ "$count" = "0" ]; then
      warn "No commits found on '${current}' that aren't in '${base}'."
      return 0
    fi
  fi

  if [ -z "$count" ]; then
    # Default: show commits and ask
    _show_squashable_commits "$default"
    count=$(prompt_input "How many commits to squash (from HEAD)")
    [[ "$count" =~ ^[0-9]+$ ]] || { warn "Enter a number."; return 1; }
  fi

  if [ "$count" -lt 2 ]; then
    warn "Need at least 2 commits to squash."
    return 1
  fi

  # Show what will be squashed
  echo ""
  echo -e "${BOLD}Commits that will be squashed (newest first):${RESET}"
  git log --oneline -"$count" | while IFS= read -r line; do
    echo -e "  ${DIM}${line}${RESET}"
  done
  echo ""
  warn "This rewrites local history. Only do this on commits NOT yet pushed,"
  warn "or on a private feature branch."
  echo ""

  # Build new commit message from existing ones
  local combined_msg
  combined_msg=$(git log --format="%s" --reverse -"$count" | head -10 | sed 's/^/- /')

  local new_msg
  new_msg=$(prompt_input "New combined commit message" \
    "$(git log -1 --pretty=format:'%s')")
  [ -z "$new_msg" ] && { warn "Commit message is required."; return 1; }

  confirm "Squash $count commits into one?" || return 1

  # Do the squash via soft reset + commit
  run_cmd git reset --soft "HEAD~${count}"
  run_cmd git commit -m "$new_msg"

  local new_hash
  new_hash=$(git rev-parse --short HEAD)
  success "Squashed $count commits into ${CYAN}${new_hash}${RESET}: ${new_msg}"
  hint "Run 'g push --force' to update the remote (force needed — history was rewritten)."
}

_show_squashable_commits() {
  local base="$1"
  local count
  count=$(git rev-list --count "${base}..HEAD" 2>/dev/null || echo 0)
  if [ "$count" -gt 0 ]; then
    echo -e "${BOLD}Your commits not in '${base}' (${count} total):${RESET}"
    git log --oneline "${base}..HEAD" | while IFS= read -r line; do
      echo -e "  ${CYAN}${line}${RESET}"
    done
    echo ""
  fi
}

usage_squash() {
  cat <<EOF
${BOLD}g squash${RESET} — Squash multiple commits into one

${BOLD}USAGE${RESET}
  g squash <n>         # Squash last n commits
  g squash --all       # Squash all commits not in main
  g squash --into <b>  # Squash all commits not in branch <b>

${BOLD}FLAGS${RESET}
  -a, --all            Squash all commits not in the default branch (main/master)
  -b, --into <branch>  Squash commits not in a specific base branch
  -h, --help           Show this help

${BOLD}EXAMPLES${RESET}
  g squash 3           # Squash last 3 commits into one
  g squash --all       # Clean up all WIP commits before a PR
  g squash --into main # Same as --all if main is the default

${BOLD}WHEN TO USE${RESET}
  Before merging a PR with many "WIP: ..." commits.
  To turn 5 "fix typo" commits into one clean "feat: add X" commit.

${BOLD}SECURITY NOTE${RESET}
  This rewrites history. Only use on branches not shared with others,
  or if everyone agrees to force-push. After squashing, run 'g push --force'.
EOF
}
