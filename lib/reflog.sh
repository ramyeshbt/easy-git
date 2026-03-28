#!/usr/bin/env bash
# lib/reflog.sh — g reflog: Show reflog and help recover lost commits/branches
# Usage: g reflog [--recover] [-n <count>] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_reflog() {
  require_git_repo_with_commits

  local count=20
  local recover=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)    usage_reflog; return 0 ;;
      -n|--count)   shift; count="$1"; shift ;;
      --recover|-r) recover=1; shift ;;
      *)            die "Unknown flag: $1. Use 'g reflog --help'" ;;
    esac
  done

  if [ "$recover" = "1" ]; then
    reflog_recover
  else
    reflog_show "$count"
  fi
}

reflog_show() {
  local count="$1"
  header "Recent git actions (reflog — last $count):"
  echo ""

  git reflog --format="%C(yellow)%h%C(reset) %C(cyan)%gd%C(reset) %C(green)%ar%C(reset)  %gs" \
    -n "$count" 2>/dev/null || git reflog | head -"$count"

  echo ""
  hint "To restore to a previous state: git checkout <hash> OR git reset --hard <hash>"
  hint "To recover a deleted branch:    g reflog --recover"
}

reflog_recover() {
  header "Recover lost commits or branches"
  echo ""
  echo -e "  ${CYAN}1${RESET}) Restore to a specific point in reflog"
  echo -e "  ${CYAN}2${RESET}) Recover a lost branch"
  echo -e "  ${CYAN}3${RESET}) Find a lost commit by message"
  echo ""

  local choice
  printf "%b" "${YELLOW}?${RESET} Choose [1-3]: "
  read -r choice </dev/tty

  case "$choice" in
    1) _recover_to_point ;;
    2) _recover_branch ;;
    3) _find_lost_commit ;;
    *) warn "Cancelled." ;;
  esac
}

_recover_to_point() {
  local entries=()
  while IFS= read -r line; do
    entries+=("$line")
  done < <(git reflog --format="%h %gd %ar  %gs" -n 30)

  local selected
  selected=$(fuzzy_select "Select reflog entry to restore to" "${entries[@]}")
  [ -z "$selected" ] && return 1

  local hash
  hash=$(echo "$selected" | awk '{print $1}')

  echo ""
  echo -e "${BOLD}This will:${RESET}"
  echo -e "  Reset HEAD to: ${CYAN}${hash}${RESET}"
  echo -e "  ${YELLOW}Current changes may be affected${RESET}"
  echo ""

  echo -e "How to restore:"
  echo -e "  ${CYAN}1${RESET}) Soft reset (keep changes staged)"
  echo -e "  ${CYAN}2${RESET}) Mixed reset (keep changes unstaged)"
  echo -e "  ${CYAN}3${RESET}) Hard reset (discard changes — irreversible)"
  printf "%b" "${YELLOW}?${RESET} Choose [1-3]: "
  local mode_choice
  read -r mode_choice </dev/tty

  local mode="mixed"
  case "$mode_choice" in
    1) mode="soft" ;;
    2) mode="mixed" ;;
    3) mode="hard"
       warn "HARD reset will permanently discard all changes after $hash."
       confirm "Are you absolutely sure?" || return 1
       ;;
    *) warn "Cancelled."; return 1 ;;
  esac

  run_cmd git reset "--$mode" "$hash"
  success "Restored to ${hash} (${mode} reset)"
}

_recover_branch() {
  echo ""
  info "Searching reflog for lost branch tips..."
  echo ""

  # Show all recent checkout events (branch switches, branch creations)
  git reflog --format="%h %gs %ar" | grep -E "checkout|branch" | head -20 | \
    while IFS= read -r line; do
      echo -e "  ${DIM}${line}${RESET}"
    done

  echo ""
  local hash
  hash=$(prompt_input "Enter the commit hash to create a new branch from")
  [ -z "$hash" ] && return 1

  if ! git rev-parse --verify "${hash}^{commit}" &>/dev/null; then
    die "Not a valid commit hash: $hash"
  fi

  local branch_name
  branch_name=$(prompt_input "New branch name to recover to")
  [ -z "$branch_name" ] && return 1

  run_cmd git checkout -b -- "$branch_name" "$hash"
  success "Recovered branch '${branch_name}' at ${hash}"
}

_find_lost_commit() {
  local query
  query=$(prompt_input "Search commit messages for")
  [ -z "$query" ] && return 1

  echo ""
  header "Matching commits in reflog:"
  git log --all --oneline --grep="$query" | head -20 | while IFS= read -r line; do
    echo -e "  ${CYAN}${line}${RESET}"
  done

  # Also search dangling commits
  local dangling
  dangling=$(git fsck --lost-found 2>/dev/null | grep "dangling commit" | awk '{print $3}' | head -10)
  if [ -n "$dangling" ]; then
    echo ""
    hint "Found dangling commits — checking for matches..."
    echo "$dangling" | while IFS= read -r h; do
      local msg
      msg=$(git log -1 --pretty=format:"%s" "$h" 2>/dev/null || echo "")
      if echo "$msg" | grep -qi "$query"; then
        echo -e "  ${YELLOW}${h:0:8}${RESET}  ${msg}  ${DIM}(dangling)${RESET}"
      fi
    done
  fi

  echo ""
  hint "To restore a commit: git checkout <hash>"
  hint "To make it a branch: git checkout -b my-recovery <hash>"
}

usage_reflog() {
  cat <<EOF
${BOLD}g reflog${RESET} — Show git history and recover lost work

${BOLD}USAGE${RESET}
  g reflog              # Show last 20 reflog entries
  g reflog -n 50        # Show last 50 entries
  g reflog --recover    # Guided recovery of lost commits/branches

${BOLD}FLAGS${RESET}
  -n, --count <n>   Number of entries to show (default: 20)
  --recover         Interactive recovery wizard
  -h, --help        Show this help

${BOLD}WHAT IS THE REFLOG?${RESET}
  Git records every change to HEAD — every commit, checkout, reset, merge.
  The reflog is your safety net. Even if you "lose" a commit with reset --hard
  or delete a branch, it's usually still in the reflog for ~90 days.

${BOLD}EXAMPLES${RESET}
  g reflog                 # "What did I do in the last hour?"
  g reflog --recover       # "I accidentally reset --hard, help!"
  g reflog -n 50           # Show more history
EOF
}
