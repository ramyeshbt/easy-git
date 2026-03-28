#!/usr/bin/env bash
# lib/conflict.sh — g conflict: Guided merge conflict resolution
# Usage: g conflict [list|edit|resolve|abort] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_conflict() {
  require_git_repo

  case "${1:-}" in
    -h|--help)   usage_conflict; return 0 ;;
    list|l)      conflict_list; return 0 ;;
    edit|e)      shift; conflict_edit "$@" ;;
    resolve|r)   shift; conflict_resolve "$@" ;;
    abort|a)     conflict_abort ;;
    "")          conflict_status ;;
    *)           die "Unknown conflict command: '$1'. Use 'g conflict --help'." ;;
  esac
}

conflict_status() {
  local conflicts
  conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null)

  if [ -z "$conflicts" ]; then
    # Check if we're in a merge/rebase in progress
    if _in_merge; then
      success "All conflicts resolved!"
      hint "Run: git merge --continue"
    elif _in_rebase; then
      success "All conflicts resolved!"
      hint "Run: git rebase --continue"
    elif _in_cherry_pick; then
      success "All conflicts resolved!"
      hint "Run: git cherry-pick --continue"
    else
      info "No conflicts in progress."
    fi
    return 0
  fi

  local count
  count=$(echo "$conflicts" | wc -l | tr -d ' ')

  header "Merge conflicts ($count file(s)):"
  echo ""

  echo "$conflicts" | while IFS= read -r f; do
    local markers
    markers=$(grep -c "^<<<<<<< " "$f" 2>/dev/null || echo 0)
    echo -e "  ${RED}✗${RESET}  ${BOLD}${f}${RESET}  ${DIM}(${markers} conflict block(s))${RESET}"
  done

  echo ""
  _show_context_hint
  echo ""

  echo -e "${BOLD}Options:${RESET}"
  echo -e "  ${CYAN}g conflict edit${RESET}      Open conflicted files in your editor"
  echo -e "  ${CYAN}g conflict resolve${RESET}   Mark a file as resolved (after editing)"
  echo -e "  ${CYAN}g conflict abort${RESET}     Abort the merge/rebase entirely"
}

conflict_list() {
  local conflicts
  conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null)

  if [ -z "$conflicts" ]; then
    info "No conflicted files."
    return 0
  fi

  echo "$conflicts" | while IFS= read -r f; do
    echo -e "${RED}${f}${RESET}"
  done
}

conflict_edit() {
  local conflicts
  conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null)

  if [ -z "$conflicts" ]; then
    info "No conflicted files to edit."
    return 0
  fi

  local target="${1:-}"
  if [ -z "$target" ]; then
    local conflict_list=()
    while IFS= read -r f; do conflict_list+=("$f"); done <<< "$conflicts"

    if [ "${#conflict_list[@]}" -eq 1 ]; then
      target="${conflict_list[0]}"
    else
      target=$(fuzzy_select "Edit conflicted file" "${conflict_list[@]}")
      [ -z "$target" ] && return 1
    fi
  fi

  local editor="${VISUAL:-${EDITOR:-vi}}"
  info "Opening '$target' in $editor..."
  info "Look for <<<<<<< HEAD ... ======= ... >>>>>>> markers and resolve them."
  echo ""

  run_cmd "$editor" "$target"

  # After editing, check if conflicts were resolved
  if grep -q "^<<<<<<< " "$target" 2>/dev/null; then
    warn "File still has conflict markers — not yet fully resolved."
  else
    if confirm "Mark '$target' as resolved?"; then
      conflict_resolve "$target"
    fi
  fi
}

conflict_resolve() {
  local target="${1:-}"

  if [ -z "$target" ]; then
    local conflicts
    conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null)
    [ -z "$conflicts" ] && { info "No conflicted files."; return 0; }

    local conflict_list=()
    while IFS= read -r f; do conflict_list+=("$f"); done <<< "$conflicts"
    target=$(fuzzy_select "Mark as resolved" "${conflict_list[@]}")
    [ -z "$target" ] && return 1
  fi

  # Verify no remaining conflict markers
  if grep -q "^<<<<<<< " "$target" 2>/dev/null; then
    warn "File '$target' still has conflict markers (<<<<<<< HEAD)."
    warn "Edit the file and remove ALL conflict markers before marking resolved."
    return 1
  fi

  run_cmd git add -- "$target"
  success "'${target}' marked as resolved."

  # Check if all conflicts are resolved now
  local remaining
  remaining=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' ')
  if [ "$remaining" = "0" ]; then
    success "All conflicts resolved!"
    _show_continue_hint
  else
    hint "${remaining} file(s) still have conflicts. Run 'g conflict' to see them."
  fi
}

conflict_abort() {
  if _in_rebase; then
    warn "This will abort the rebase and return to the pre-rebase state."
    confirm "Abort rebase?" || return 1
    run_cmd git rebase --abort
    success "Rebase aborted."
  elif _in_merge; then
    warn "This will abort the merge and return to the pre-merge state."
    confirm "Abort merge?" || return 1
    run_cmd git merge --abort
    success "Merge aborted."
  elif _in_cherry_pick; then
    warn "This will abort the cherry-pick."
    confirm "Abort cherry-pick?" || return 1
    run_cmd git cherry-pick --abort
    success "Cherry-pick aborted."
  else
    warn "No merge, rebase, or cherry-pick in progress."
  fi
}

_in_merge()       { [ -f "$(git_root)/.git/MERGE_HEAD" ]; }
_in_rebase()      { [ -d "$(git_root)/.git/rebase-merge" ] || [ -d "$(git_root)/.git/rebase-apply" ]; }
_in_cherry_pick() { [ -f "$(git_root)/.git/CHERRY_PICK_HEAD" ]; }

_show_context_hint() {
  if _in_rebase; then
    info "In progress: ${BOLD}rebase${RESET}"
    hint "After resolving all conflicts: git add <files> && git rebase --continue"
    hint "To cancel:                     g conflict abort"
  elif _in_merge; then
    info "In progress: ${BOLD}merge${RESET}"
    hint "After resolving all conflicts: git add <files> && git merge --continue"
    hint "To cancel:                     g conflict abort"
  elif _in_cherry_pick; then
    info "In progress: ${BOLD}cherry-pick${RESET}"
    hint "After resolving all conflicts: git add <files> && git cherry-pick --continue"
    hint "To cancel:                     g conflict abort"
  fi
}

_show_continue_hint() {
  if _in_rebase;       then hint "Run: git rebase --continue"; fi
  if _in_merge;        then hint "Run: git merge --continue OR g commit"; fi
  if _in_cherry_pick;  then hint "Run: git cherry-pick --continue"; fi
}

usage_conflict() {
  cat <<EOF
${BOLD}g conflict${RESET} — Guided merge conflict resolution

${BOLD}USAGE${RESET}
  g conflict             # Show all conflicted files with guidance
  g conflict list        # List conflicted file paths (scriptable)
  g conflict edit        # Open a conflicted file in your editor
  g conflict resolve     # Mark a file as resolved (git add)
  g conflict abort       # Abort the merge, rebase, or cherry-pick

${BOLD}EXAMPLES${RESET}
  g conflict             # See what's conflicted and what to do
  g conflict edit        # Open the conflicted file in \$EDITOR
  g conflict resolve     # Mark file as done after editing
  g conflict abort       # Give up — return to pre-merge state

${BOLD}HOW TO RESOLVE A CONFLICT${RESET}
  1. Run 'g conflict' to see which files have conflicts
  2. Open each file — look for markers:
       <<<<<<< HEAD
       your changes
       =======
       their changes
       >>>>>>> branch-name
  3. Edit the file to keep what you want (delete the markers)
  4. Run 'g conflict resolve <file>'
  5. Repeat for each conflicted file
  6. Run 'git merge --continue' or 'git rebase --continue'
EOF
}
