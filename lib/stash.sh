#!/usr/bin/env bash
# lib/stash.sh — g stash: Named stash management (save/pop/list/drop/show)
# Usage: g stash [save|pop|list|drop|show] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_stash() {
  require_git_repo

  case "${1:-}" in
    -h|--help)   usage_stash; return 0 ;;
    save|s)      shift; stash_save "$@" ;;
    pop|p)       shift; stash_pop "$@" ;;
    list|l)      stash_list ;;
    drop|d)      shift; stash_drop "$@" ;;
    show)        shift; stash_show "$@" ;;
    "")          stash_save ;;  # bare `g stash` saves with auto-name
    *)           die "Unknown stash command: '$1'. Use 'g stash --help'." ;;
  esac
}

stash_save() {
  if ! is_dirty; then
    warn "Nothing to stash — working tree is clean."
    return 0
  fi

  local name="${1:-}"
  if [ -z "$name" ]; then
    local branch
    branch=$(current_branch)
    local ts
    ts=$(date '+%m-%d %H:%M')
    name="${branch}: ${ts}"
  fi

  run_cmd git stash push -m "$name"
  success "Stashed as: ${BOLD}${name}${RESET}"
  hint "Run 'g stash pop' to restore. 'g stash list' to see all stashes."
}

stash_pop() {
  local stash_count
  stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

  if [ "$stash_count" = "0" ]; then
    warn "No stashes to pop."
    return 0
  fi

  if [ "$stash_count" = "1" ] || [ -n "${1:-}" ]; then
    local ref="${1:-}"
    [ -z "$ref" ] && ref='stash@{0}'  # avoid nested-brace expansion bug
    # Validate stash ref format to prevent flag injection
    if ! [[ "$ref" =~ ^stash@\{[0-9]+\}$ ]]; then
      _stash_ref_error "$ref" "pop"
    fi
    run_cmd git stash pop "$ref"
    success "Stash restored."
    return 0
  fi

  # Multiple stashes — let user pick
  local stash_list=()
  while IFS= read -r line; do
    stash_list+=("$line")
  done < <(git stash list)

  local selected
  selected=$(fuzzy_select "Select stash to pop" "${stash_list[@]}")
  [ -z "$selected" ] && return 1

  local ref
  ref=$(echo "$selected" | grep -oE 'stash@\{[0-9]+\}')
  run_cmd git stash pop "$ref"
  success "Stash restored."
}

stash_list() {
  local stash_count
  stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

  if [ "$stash_count" = "0" ]; then
    info "No stashes saved."
    return 0
  fi

  header "Saved stashes (${stash_count}):"
  _print_stash_entries
  echo ""
  hint "g stash pop  [stash@{N}]   — restore a stash (interactive if omitted)"
  hint "g stash drop [stash@{N}]   — discard a stash (interactive if omitted)"
  hint "g stash show [stash@{N}]   — preview a stash (interactive if omitted)"
  hint "Example: g stash drop stash@{0}"
}

# Print stash entries with index and message — shared by list and error paths
_print_stash_entries() {
  while IFS= read -r line; do
    local ref msg
    ref=$(echo "$line" | grep -oE 'stash@\{[0-9]+\}')
    msg="${line#*: }"  # pure bash — safe from sed delimiter injection
    echo -e "  ${CYAN}${ref}${RESET}  ${msg}"
  done < <(git stash list)
}

# Show available stashes inline when user provided an invalid/unknown ref
_stash_ref_error() {
  local bad_ref="$1"
  local action="$2"
  local stash_count
  stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
  echo ""
  error "Invalid stash reference: '${bad_ref}'"
  echo -e "  ${DIM}Expected format: stash@{N}  (e.g. stash@{0}, stash@{1})${RESET}"
  echo ""
  if [[ "$stash_count" -gt 0 ]]; then
    echo -e "${BOLD}Available stashes:${RESET}"
    _print_stash_entries
    echo ""
    hint "Run 'g stash ${action}' (no argument) for interactive selection."
    hint "Or:  g stash ${action} stash@{0}"
  fi
  exit 1
}

stash_drop() {
  local stash_count
  stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

  if [ "$stash_count" = "0" ]; then
    warn "No stashes to drop."
    return 0
  fi

  local ref="${1:-}"

  if [ -z "$ref" ]; then
    local stash_list=()
    while IFS= read -r line; do
      stash_list+=("$line")
    done < <(git stash list)

    local selected
    selected=$(fuzzy_select "Select stash to drop" "${stash_list[@]}")
    [ -z "$selected" ] && return 1
    ref=$(echo "$selected" | grep -oE 'stash@\{[0-9]+\}')
  fi

  # Validate stash ref format
  if ! [[ "$ref" =~ ^stash@\{[0-9]+\}$ ]]; then
    _stash_ref_error "$ref" "drop"
  fi

  confirm "Drop stash '${ref}'? This cannot be undone." || return 1
  run_cmd git stash drop "$ref"
  success "Stash '${ref}' dropped."
}

stash_show() {
  local stash_count
  stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

  if [ "$stash_count" = "0" ]; then
    warn "No stashes to show."
    return 0
  fi

  local ref="${1:-}"

  if [ -z "$ref" ] && [ "$stash_count" -gt 1 ]; then
    local stash_list=()
    while IFS= read -r line; do
      stash_list+=("$line")
    done < <(git stash list)

    local selected
    selected=$(fuzzy_select "Show stash" "${stash_list[@]}")
    [ -z "$selected" ] && return 1
    ref=$(echo "$selected" | grep -oE 'stash@\{[0-9]+\}')
  fi

  [ -z "$ref" ] && ref='stash@{0}'  # avoid nested-brace expansion bug
  # Validate stash ref format
  if ! [[ "$ref" =~ ^stash@\{[0-9]+\}$ ]]; then
    _stash_ref_error "$ref" "show"
  fi
  git stash show -p "$ref"
}

usage_stash() {
  cat <<EOF
${BOLD}g stash${RESET} — Named stash management

${BOLD}USAGE${RESET}
  g stash                       # Save with auto-name (branch + timestamp)
  g stash save [name]           # Save with custom name
  g stash pop  [stash@{N}]      # Restore a stash (interactive picker if omitted)
  g stash list                  # Show all saved stashes with their refs
  g stash drop [stash@{N}]      # Delete a stash (interactive picker if omitted)
  g stash show [stash@{N}]      # Preview stash diff (interactive picker if omitted)

${BOLD}STASH REFS${RESET}
  Stashes are referenced as stash@{0}, stash@{1}, etc.
  stash@{0} is always the most recently saved stash.
  Run 'g stash list' to see all refs with their names.

${BOLD}EXAMPLES${RESET}
  g stash                        # Quick save
  g stash save "WIP: auth fix"   # Named save
  g stash list                   # See refs: stash@{0}, stash@{1}, ...
  g stash pop                    # Restore latest (or pick interactively)
  g stash pop  stash@{1}         # Restore a specific stash by ref
  g stash drop stash@{0}         # Drop the most recent stash
  g stash drop                   # Pick a stash to drop interactively
  g stash show stash@{0}         # Preview what stash@{0} contains
EOF
}
