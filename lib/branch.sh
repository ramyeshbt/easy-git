#!/usr/bin/env bash
# lib/branch.sh — g branch: Create, switch, delete branches with fuzzy search
# Usage: g branch [name] [-d] [-D] [-l] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_branch() {
  require_git_repo

  case "${1:-}" in
    -h|--help)    usage_branch; return 0 ;;
    -l|--list)    list_branches; return 0 ;;
    -d|--delete)  shift; delete_branch "$@"; return $? ;;
    -D|--force-delete) shift; delete_branch --force "$@"; return $? ;;
    -r|--rename)  shift; rename_branch "$@"; return $? ;;
    "")           switch_branch; return $? ;;
    *)            create_or_switch_branch "$1"; return $? ;;
  esac
}

# List all local branches with current marker and tracking info
list_branches() {
  local current
  current=$(current_branch)
  header "Local branches:"
  git branch -vv | while IFS= read -r line; do
    if [[ "$line" == *"* "* ]]; then
      echo -e "  ${GREEN}${line}${RESET}"
    else
      echo -e "  ${line}"
    fi
  done

  local remote_count
  remote_count=$(git branch -r 2>/dev/null | grep -v HEAD | wc -l | tr -d ' ')
  if [ "$remote_count" -gt 0 ]; then
    hint "Use 'g branch -r' to see $remote_count remote branches"
  fi
}

# Interactive branch switcher
switch_branch() {
  require_git_repo_with_commits

  local current
  current=$(current_branch)

  # Collect all local branches except current
  local branches=()
  while IFS= read -r b; do
    b="${b#  }"  # trim leading spaces
    b="${b#* }"  # remove potential * marker
    b="${b# }"
    branches+=("$b")
  done < <(git branch | grep -v "^\* " | sed 's/^  //')

  if [ "${#branches[@]}" -eq 0 ]; then
    warn "No other local branches. Create one with: g branch <name>"
    return 1
  fi

  local target
  target=$(fuzzy_select "Switch to branch" "${branches[@]}")
  [ -z "$target" ] && return 1

  _do_switch "$target"
}

# Create a new branch or switch if it already exists
create_or_switch_branch() {
  local name="$1"

  # Reject flag injection: names starting with - look like git flags
  case "$name" in
    -*) error "Branch name cannot start with '-': '$name'"; return 1 ;;
  esac

  # Sanitize branch name — strip shell-dangerous chars
  local safe_name
  safe_name=$(echo "$name" \
    | sed 's/[[:space:]]/-/g' \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-zA-Z0-9._/\-]//g')   # whitelist: alphanumeric, dot, dash, slash, underscore

  # Prevent git lock-file collision: must not end with .lock
  safe_name="${safe_name%.lock}"

  # Prevent empty name after sanitization
  if [ -z "$safe_name" ]; then
    die "Branch name '$name' is invalid after sanitization — use alphanumeric characters."
  fi

  # Already exists locally?
  if git show-ref --verify --quiet "refs/heads/$safe_name"; then
    info "Branch '$safe_name' already exists — switching."
    _do_switch "$safe_name"
    return $?
  fi

  # Exists on remote?
  if git show-ref --verify --quiet "refs/remotes/origin/$safe_name"; then
    if confirm "Branch '$safe_name' exists on remote. Track it locally?"; then
      run_cmd git checkout --track -- "origin/$safe_name"
      success "Switched to '$safe_name' (tracking origin/$safe_name)"
      return 0
    fi
  fi

  # Create new branch
  local base
  base=$(default_branch)
  info "Creating branch '${BOLD}${safe_name}${RESET}' from ${CYAN}${base}${RESET}"

  if is_dirty; then
    warn "You have uncommitted changes."
    if confirm "Stash them before switching?"; then
      run_cmd git stash push -m "auto-stash before branch $safe_name"
      run_cmd git checkout -b -- "$safe_name" "$base" 2>/dev/null || run_cmd git checkout -b -- "$safe_name"
      run_cmd git stash pop
    else
      run_cmd git checkout -b -- "$safe_name"
    fi
  else
    run_cmd git checkout -b -- "$safe_name"
  fi

  success "Created and switched to '${BOLD}${safe_name}${RESET}'"
  hint "Run 'g push' to push this branch to the remote."
}

_do_switch() {
  local target="$1"
  local current
  current=$(current_branch)

  if [ "$target" = "$current" ]; then
    info "Already on '$target'"
    return 0
  fi

  if is_dirty; then
    warn "You have uncommitted changes."
    if confirm "Stash them before switching?"; then
      run_cmd git stash push -m "auto-stash switching to $target"
      run_cmd git checkout -- "$target"
      run_cmd git stash pop
      success "Switched to '${BOLD}${target}${RESET}' (stash restored)"
    else
      run_cmd git checkout -- "$target"
      success "Switched to '${BOLD}${target}${RESET}'"
    fi
  else
    run_cmd git checkout -- "$target"
    success "Switched to '${BOLD}${target}${RESET}'"
  fi
}

delete_branch() {
  local force=0
  local name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f) force=1; shift ;;
      *) name="$1"; shift ;;
    esac
  done

  # If no name, pick interactively
  if [ -z "$name" ]; then
    local current
    current=$(current_branch)
    local branches=()
    while IFS= read -r b; do
      branches+=("${b#  }")
    done < <(git branch | grep -v "^\* " | sed 's/^  //')

    [ "${#branches[@]}" -eq 0 ] && { warn "No other branches to delete."; return 1; }

    name=$(fuzzy_select "Delete branch" "${branches[@]}")
    [ -z "$name" ] && return 1
  fi

  local current
  current=$(current_branch)
  if [ "$name" = "$current" ]; then
    die "Cannot delete the currently checked-out branch '$name'."
  fi

  local default
  default=$(default_branch)
  if [ "$name" = "$default" ]; then
    die "Cannot delete the default branch '$name'."
  fi

  if [ "$force" = "1" ]; then
    if confirm "Force-delete branch '${name}'? (unmerged commits will be lost)"; then
      run_cmd git branch -D -- "$name"
      success "Force-deleted branch '${name}'"
    fi
  else
    run_cmd git branch -d -- "$name" || {
      warn "Branch '$name' is not fully merged."
      if confirm "Force-delete anyway? (unmerged commits will be lost)"; then
        run_cmd git branch -D -- "$name"
        success "Force-deleted branch '${name}'"
      fi
    }
    success "Deleted branch '${name}'"
  fi
}

rename_branch() {
  local old_name="${1:-}"
  local new_name="${2:-}"

  if [ -z "$old_name" ]; then
    old_name=$(current_branch)
    new_name=$(prompt_input "New name for branch '${old_name}'")
  elif [ -z "$new_name" ]; then
    new_name=$(prompt_input "New name for branch '${old_name}'")
  fi

  [ -z "$new_name" ] && { warn "No new name provided."; return 1; }

  # Sanitize new branch name using same rules as create
  new_name=$(echo "$new_name" | sed 's/[[:space:]]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-zA-Z0-9._/\-]//g')
  new_name="${new_name#-}"; new_name="${new_name#-}"; new_name="${new_name%.lock}"
  [ -z "$new_name" ] && die "New branch name is invalid after sanitization."

  run_cmd git branch -m -- "$old_name" "$new_name"
  success "Renamed '${old_name}' → '${new_name}'"

  # Offer to update remote
  if git show-ref --verify --quiet "refs/remotes/origin/$old_name"; then
    if confirm "Update remote branch too? (delete old, push new)"; then
      run_cmd git push origin --delete -- "$old_name"
      run_cmd git push -u origin -- "$new_name"
    fi
  fi
}

usage_branch() {
  cat <<EOF
${BOLD}g branch${RESET} — Branch management

${BOLD}USAGE${RESET}
  g branch                     # Interactive branch switcher
  g branch <name>              # Create or switch to branch
  g branch -l                  # List all local branches
  g branch -d [name]           # Delete branch (safe — merged only)
  g branch -D [name]           # Force-delete branch
  g branch -r <old> <new>      # Rename branch

${BOLD}FLAGS${RESET}
  -l, --list           List branches
  -d, --delete         Delete branch (merged only)
  -D, --force-delete   Force-delete branch
  -r, --rename         Rename branch
  -h, --help           Show this help

${BOLD}EXAMPLES${RESET}
  g branch                     # Fuzzy pick + switch
  g branch feat/PROJ-123-auth  # Create feature branch
  g branch -d old-branch       # Delete merged branch
  g branch -r old-name new-name
EOF
}
