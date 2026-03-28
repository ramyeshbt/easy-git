#!/usr/bin/env bash
# lib/clean.sh — g clean: Remove merged branches and gone remote branches
# Usage: g clean [--dry-run] [--gone] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_clean() {
  require_git_repo_with_commits

  local dry_run=0
  local gone_only=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)   usage_clean; return 0 ;;
      -n|--dry-run) dry_run=1; shift ;;
      --gone)      gone_only=1; shift ;;
      *)           die "Unknown flag: $1. Use 'g clean --help'" ;;
    esac
  done

  if [ "$dry_run" = "1" ]; then
    info "Dry run — no branches will be deleted."
    echo ""
  fi

  # Fetch to update remote tracking info
  info "Fetching remote info..."
  git fetch --prune --quiet 2>/dev/null || warn "Could not fetch from remote."

  local current default
  current=$(current_branch)
  default=$(default_branch)

  local merged_branches=()
  local gone_branches=()

  # Find merged branches
  if [ "$gone_only" = "0" ]; then
    while IFS= read -r branch; do
      branch="${branch#  }"
      branch="${branch# }"
      [ "$branch" = "$current" ] && continue
      [ "$branch" = "$default" ] && continue
      [ -z "$branch" ] && continue
      merged_branches+=("$branch")
    done < <(git branch --merged "$default" | grep -v "^\* " | grep -v "^  $default$")
  fi

  # Find gone branches (remote was deleted)
  while IFS= read -r line; do
    if [[ "$line" == *": gone]"* ]]; then
      local branch
      branch=$(echo "$line" | awk '{print $1}' | sed 's/^[ *]*//')
      [ "$branch" = "$current" ] && continue
      [ "$branch" = "$default" ] && continue
      [ -z "$branch" ] && continue
      gone_branches+=("$branch")
    fi
  done < <(git branch -vv | grep ': gone\]')

  # Report findings
  local total=$(( ${#merged_branches[@]} + ${#gone_branches[@]} ))
  if [ "$total" = "0" ]; then
    success "No stale branches found — all clean!"
    return 0
  fi

  if [ "${#merged_branches[@]}" -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}Merged branches (safe to delete):${RESET}"
    for b in "${merged_branches[@]}"; do
      local last_commit
      last_commit=$(git log -1 --pretty=format:"%h %s" "$b" 2>/dev/null || echo "unknown")
      echo -e "  ${CYAN}${b}${RESET} — ${DIM}${last_commit}${RESET}"
    done
    echo ""
  fi

  if [ "${#gone_branches[@]}" -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}Gone branches (remote was deleted):${RESET}"
    for b in "${gone_branches[@]}"; do
      local last_commit
      last_commit=$(git log -1 --pretty=format:"%h %s" "$b" 2>/dev/null || echo "unknown")
      echo -e "  ${MAGENTA}${b}${RESET} — ${DIM}${last_commit}${RESET}"
    done
    echo ""
  fi

  if [ "$dry_run" = "1" ]; then
    info "Dry run complete. Run 'g clean' (without --dry-run) to delete these branches."
    return 0
  fi

  confirm "Delete all ${total} stale branch(es)?" || return 1

  local deleted=0
  for b in "${merged_branches[@]}" "${gone_branches[@]}"; do
    if git branch -d -- "$b" 2>/dev/null || git branch -D -- "$b" 2>/dev/null; then
      echo -e "  ${GREEN}✓${RESET} Deleted: ${b}"
      deleted=$((deleted + 1))
    else
      echo -e "  ${RED}✗${RESET} Could not delete: ${b}"
    fi
  done

  success "Deleted ${deleted} branch(es)."
}

usage_clean() {
  cat <<EOF
${BOLD}g clean${RESET} — Remove merged and gone branches

${BOLD}USAGE${RESET}
  g clean [flags]

${BOLD}WHAT IT REMOVES${RESET}
  • Branches fully merged into the default branch (main/master)
  • Branches whose remote was deleted (marked as 'gone')

${BOLD}FLAGS${RESET}
  -n, --dry-run   Preview what would be deleted (no action)
  --gone          Only remove 'gone' branches (remote deleted)
  -h, --help      Show this help

${BOLD}EXAMPLES${RESET}
  g clean --dry-run    # Preview stale branches
  g clean              # Delete all stale branches (with confirmation)
  g clean --gone       # Only delete branches whose remote was deleted
EOF
}
