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
    local ref="${1:-stash@{0}}"
    # Validate stash ref format to prevent flag injection
    if ! [[ "$ref" =~ ^stash@\{[0-9]+\}$ ]]; then
      die "Invalid stash reference: '$ref'. Expected format: stash@{N}"
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
  git stash list | while IFS= read -r line; do
    # stash@{0}: On branch: message
    local ref msg
    ref=$(echo "$line" | grep -oE 'stash@\{[0-9]+\}')
    msg="${line#*: }"  # pure bash — safe from sed delimiter injection
    echo -e "  ${CYAN}${ref}${RESET}  ${msg}"
  done
  echo ""
  hint "g stash pop      — restore latest stash"
  hint "g stash drop     — discard a stash"
  hint "g stash show     — preview a stash"
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
    die "Invalid stash reference: '$ref'. Expected format: stash@{N}"
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

  ref="${ref:-stash@{0}}"
  # Validate stash ref format
  if ! [[ "$ref" =~ ^stash@\{[0-9]+\}$ ]]; then
    die "Invalid stash reference: '$ref'. Expected format: stash@{N}"
  fi
  git stash show -p "$ref"
}

usage_stash() {
  cat <<EOF
${BOLD}g stash${RESET} — Named stash management

${BOLD}USAGE${RESET}
  g stash              # Save with auto-name (branch + timestamp)
  g stash save [name]  # Save with custom name
  g stash pop          # Restore latest stash (interactive if multiple)
  g stash list         # Show all saved stashes
  g stash drop [ref]   # Delete a stash
  g stash show [ref]   # Preview stash diff

${BOLD}EXAMPLES${RESET}
  g stash                      # Quick save
  g stash save "WIP: auth fix" # Named save
  g stash pop                  # Restore latest
  g stash list                 # See all stashes
EOF
}
