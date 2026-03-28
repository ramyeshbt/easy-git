#!/usr/bin/env bash
# lib/sync.sh — g sync: Sync current branch with main/master
# Automatically stashes, pulls base, rebases, restores stash.
# Usage: g sync [--merge] [--no-rebase] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_sync() {
  require_git_repo_with_commits

  local use_merge=0
  local base_override=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)    usage_sync; return 0 ;;
      --merge)      use_merge=1; shift ;;
      --onto)       shift; base_override="$1"; shift ;;
      *)            die "Unknown flag: $1. Use 'g sync --help'" ;;
    esac
  done

  local current remote base stashed

  current=$(current_branch)
  remote=$(default_remote)

  # Sanitize --onto argument (same whitelist as branch.sh)
  if [ -n "$base_override" ]; then
    local safe_base
    safe_base=$(echo "$base_override" | sed 's/[^a-zA-Z0-9._/\-]//g')
    safe_base="${safe_base#-}"  # strip leading dash (flag injection)
    [ -z "$safe_base" ] && die "Invalid branch name for --onto: '$base_override'"
    base="$safe_base"
  else
    base=$(default_branch)
  fi
  stashed=0

  if [ -z "$current" ]; then
    die "You are in a detached HEAD state. Checkout a branch first."
  fi

  header "Syncing '${current}' with '${base}'..."

  # Step 1: Stash any dirty state
  if is_dirty; then
    info "Stashing uncommitted changes..."
    run_cmd git stash push -m "g-sync auto-stash $(date '+%Y-%m-%d %H:%M')"
    stashed=1
  fi

  # Step 2: Fetch latest from remote
  info "Fetching from ${remote}..."
  run_cmd git fetch "$remote" --prune || {
    warn "Could not fetch from remote '${remote}'. Proceeding with local branches."
  }

  # Step 3: Update base branch
  if [ "$current" != "$base" ]; then
    info "Updating ${base}..."
    run_cmd git checkout -- "$base"
    run_cmd git pull "$remote" -- "$base" --ff-only || {
      warn "Could not fast-forward ${base}. You may need to resolve conflicts manually."
      run_cmd git checkout -- "$current"
      _restore_stash "$stashed"
      return 1
    }
    run_cmd git checkout -- "$current"
  fi

  # Step 4: Rebase or merge
  if [ "$use_merge" = "1" ]; then
    info "Merging ${base} into ${current}..."
    if ! run_cmd git merge -- "$base" --no-edit; then
      error "Merge conflict detected!"
      echo ""
      git status --short | grep "^UU\|^AA\|^DD" | sed 's/^/  Conflict: /'
      echo ""
      hint "Resolve conflicts, then run: git add . && git merge --continue"
      hint "Or abort with: git merge --abort"
      _restore_stash "$stashed"
      return 1
    fi
  else
    info "Rebasing ${current} onto ${base}..."
    if ! run_cmd git rebase -- "$base"; then
      error "Rebase conflict detected!"
      echo ""
      git status --short | grep "^UU\|^AA\|^DD\|^U" | sed 's/^/  Conflict: /'
      echo ""
      hint "Resolve conflicts, then run: git add . && git rebase --continue"
      hint "Or abort with: git rebase --abort"
      _restore_stash "$stashed"
      return 1
    fi
  fi

  # Step 5: Restore stash
  _restore_stash "$stashed"

  success "Branch '${BOLD}${current}${RESET}' is up to date with '${CYAN}${base}${RESET}'"

  # Show how many commits ahead
  local ahead
  ahead=$(commits_ahead)
  if [ "$ahead" -gt 0 ]; then
    hint "${ahead} commit(s) ahead of origin/${current} — run 'g push' when ready."
  fi
}

_restore_stash() {
  local stashed="$1"
  if [ "$stashed" = "1" ]; then
    info "Restoring stashed changes..."
    if ! run_cmd git stash pop; then
      warn "Stash pop had conflicts. Check 'git stash list' to recover manually."
    fi
  fi
}

usage_sync() {
  cat <<EOF
${BOLD}g sync${RESET} — Sync current branch with main/master

${BOLD}USAGE${RESET}
  g sync [flags]

${BOLD}WHAT IT DOES${RESET}
  1. Stash any dirty working tree
  2. Fetch from remote
  3. Fast-forward the base branch (main/master)
  4. Rebase your branch onto it (or merge with --merge)
  5. Restore stash

${BOLD}FLAGS${RESET}
  --merge          Use merge instead of rebase
  --onto <branch>  Sync with a specific branch instead of main
  -h, --help       Show this help

${BOLD}EXAMPLES${RESET}
  g sync                       # Rebase current branch onto main
  g sync --merge               # Merge main into current branch
  g sync --onto develop        # Sync with 'develop' branch
EOF
}
