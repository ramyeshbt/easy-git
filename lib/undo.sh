#!/usr/bin/env bash
# lib/undo.sh — g undo: Safe undo — always shows what will happen before doing it
# Usage: g undo [commit|push|file <path>] [--hard] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_undo() {
  require_git_repo

  case "${1:-}" in
    -h|--help) usage_undo; return 0 ;;
    commit)    shift; undo_commit "$@" ;;
    push)      shift; undo_push "$@" ;;
    file)      shift; undo_file "$@" ;;
    "")        undo_last ;;
    *)         die "Unknown undo target: '$1'. Use: commit, push, file, or no argument." ;;
  esac
}

# Default: show what we can undo and pick
undo_last() {
  require_git_repo_with_commits

  header "What do you want to undo?"
  echo ""
  echo -e "  ${CYAN}1${RESET}) Last commit (keep changes staged)"
  echo -e "  ${CYAN}2${RESET}) Last commit (keep changes unstaged)"
  echo -e "  ${CYAN}3${RESET}) Last commit (DISCARD changes — irreversible)"
  echo -e "  ${CYAN}4${RESET}) All unstaged changes to tracked files"
  echo -e "  ${CYAN}5${RESET}) Specific file changes"
  echo ""

  local choice
  printf "%b" "${YELLOW}?${RESET} Choose [1-5]: "
  if [ -t 0 ]; then
    read -r choice </dev/tty
  else
    read -r choice
  fi

  case "$choice" in
    1) undo_commit --soft ;;
    2) undo_commit ;;
    3) undo_commit --hard ;;
    4) undo_all_unstaged ;;
    5) undo_file_interactive ;;
    *) warn "Cancelled." ;;
  esac
}

undo_commit() {
  require_git_repo_with_commits

  local mode="mixed"  # default: unstaged
  local yes=0

  # Auto-confirm when stdin is not a TTY (non-interactive environments)
  [ ! -t 0 ] && yes=1

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --soft)  mode="soft";  shift ;;
      --hard)  mode="hard";  shift ;;
      --mixed) mode="mixed"; shift ;;
      -y|--yes) yes=1;       shift ;;
      *) die "Unknown flag: $1" ;;
    esac
  done

  local last_commit last_msg
  last_commit=$(git rev-parse --short HEAD)
  last_msg=$(git log -1 --pretty=format:"%s")

  echo ""
  echo -e "${BOLD}Last commit:${RESET}"
  echo -e "  ${CYAN}${last_commit}${RESET} ${last_msg}"
  echo ""

  case "$mode" in
    soft)
      echo -e "  ${GREEN}Effect:${RESET} Commit will be removed, changes will stay ${BOLD}staged${RESET}"
      ;;
    mixed)
      echo -e "  ${YELLOW}Effect:${RESET} Commit will be removed, changes will be ${BOLD}unstaged${RESET}"
      ;;
    hard)
      echo -e "  ${RED}Effect:${RESET} Commit will be removed, changes will be ${BOLD}permanently discarded${RESET}"
      ;;
  esac
  echo ""

  if [ "$yes" -eq 0 ]; then
    confirm "Undo this commit?" || return 1
  fi

  run_cmd git reset "--${mode}" HEAD~1

  case "$mode" in
    soft)   success "Commit undone — changes are still staged." ;;
    mixed)  success "Commit undone — changes are in your working tree." ;;
    hard)   success "Commit discarded." ;;
  esac
}

undo_push() {
  require_git_repo_with_commits

  local branch remote upstream

  branch=$(current_branch)
  remote=$(default_remote)
  upstream="${remote}/${branch}"

  if ! git show-ref --verify --quiet "refs/remotes/${upstream}"; then
    die "No remote tracking branch found for '${branch}'."
  fi

  local remote_head local_head
  remote_head=$(git rev-parse --short "${upstream}")
  local_head=$(git rev-parse --short HEAD)

  if [ "$remote_head" = "$local_head" ]; then
    warn "Local and remote are the same — nothing to undo."
    return 0
  fi

  echo ""
  echo -e "${BOLD}This will:${RESET}"
  echo -e "  Force-push ${CYAN}${branch}${RESET} to reset remote to local HEAD"
  echo -e "  Remote is currently at: ${DIM}${remote_head}${RESET}"
  echo -e "  Will be reset to:        ${CYAN}${local_head}${RESET}"
  echo ""
  warn "This rewrites remote history. Only do this on private branches."
  echo ""

  confirm "Force-push to undo remote commit(s)?" || return 1
  run_cmd git push --force-with-lease "$remote" -- "$branch"
  success "Remote '${upstream}' updated."
}

undo_file() {
  local filepath="$1"

  if [ -z "$filepath" ]; then
    undo_file_interactive
    return $?
  fi

  if [ ! -f "$filepath" ] && ! git ls-files --error-unmatch "$filepath" &>/dev/null; then
    die "File not found: $filepath"
  fi

  echo ""
  echo -e "${BOLD}This will discard all uncommitted changes to:${RESET}"
  echo -e "  ${CYAN}${filepath}${RESET}"
  echo ""
  git diff -- "$filepath" | head -20
  echo ""

  confirm "Discard changes to '${filepath}'?" || return 1
  run_cmd git restore -- "$filepath"
  success "Changes to '${filepath}' discarded."
}

undo_file_interactive() {
  local changed_files=()
  while IFS= read -r line; do
    changed_files+=("$line")
  done < <(git diff --name-only)

  if [ "${#changed_files[@]}" -eq 0 ]; then
    warn "No unstaged changes to undo."
    return 0
  fi

  local target
  target=$(fuzzy_select "Select file to restore" "${changed_files[@]}")
  [ -z "$target" ] && return 1

  undo_file "$target"
}

undo_all_unstaged() {
  if ! is_dirty; then
    info "Working tree is already clean."
    return 0
  fi

  echo ""
  echo -e "${BOLD}This will discard ALL unstaged changes to tracked files:${RESET}"
  git diff --stat | sed 's/^/  /'
  echo ""
  warn "This cannot be undone."
  echo ""

  confirm "Discard all unstaged changes?" || return 1
  run_cmd git restore .
  success "All unstaged changes discarded."
}

usage_undo() {
  cat <<EOF
${BOLD}g undo${RESET} — Safe undo with preview

${BOLD}USAGE${RESET}
  g undo                    # Interactive — pick what to undo
  g undo commit [--soft]    # Undo last commit, keep changes staged
  g undo commit             # Undo last commit, keep changes unstaged
  g undo commit --hard      # Undo last commit, DISCARD changes
  g undo push               # Undo last push (force-with-lease)
  g undo file <path>        # Discard changes to a specific file

${BOLD}FLAGS${RESET}
  --soft       Keep changes staged
  --hard       Discard all changes (irreversible)
  -y, --yes    Skip confirmation prompt (auto-applied in non-TTY environments)
  -h, --help

${BOLD}EXAMPLES${RESET}
  g undo                     # Guided interactive undo
  g undo commit              # Soft undo — changes go back to working tree
  g undo commit --hard       # Full discard (careful!)
  g undo file src/main.sh    # Restore one file
EOF
}
