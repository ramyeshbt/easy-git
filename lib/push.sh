#!/usr/bin/env bash
# lib/push.sh — g push: Push with auto-upstream, force-with-lease guard
# Usage: g push [--force] [--no-pr] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_push() {
  require_git_repo_with_commits

  local force=0
  local open_pr=1
  local remote

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)    usage_push; return 0 ;;
      -f|--force)   force=1; shift ;;
      --no-pr)      open_pr=0; shift ;;
      *)            die "Unknown flag: $1. Use 'g push --help'" ;;
    esac
  done

  remote=$(default_remote)
  local branch
  branch=$(current_branch)

  if [ -z "$branch" ]; then
    die "You are in a detached HEAD state. Checkout a branch first."
  fi

  # Branch protection: warn before pushing directly to protected branches
  _check_protected_branch "$branch" "$force"

  # Check if there's anything to push
  local has_upstream
  has_upstream=$(git for-each-ref --format='%(upstream:short)' "refs/heads/$branch" 2>/dev/null)

  if [ -n "$has_upstream" ]; then
    local ahead behind
    ahead=$(commits_ahead)
    behind=$(commits_behind)

    if [ "$ahead" = "0" ] && [ "$behind" = "0" ]; then
      info "Branch '${branch}' is already up to date with remote."
      return 0
    fi

    if [ "$behind" -gt 0 ]; then
      warn "${behind} commit(s) behind remote. You may want to run 'g sync' first."
      confirm "Push anyway?" || return 1
    fi

    if [ "$force" = "1" ]; then
      warn "Force pushing '${branch}' (using --force-with-lease for safety)..."
      confirm "This will overwrite remote history. Continue?" || return 1
      run_cmd git push "$remote" -- "$branch" --force-with-lease
    else
      run_cmd git push "$remote" -- "$branch"
    fi
  else
    # No upstream — set it
    info "Setting upstream to ${remote}/${branch}..."
    if [ "$force" = "1" ]; then
      run_cmd git push -u "$remote" -- "$branch" --force-with-lease
    else
      run_cmd git push -u "$remote" -- "$branch"
    fi
  fi

  success "Pushed '${BOLD}${branch}${RESET}' to ${CYAN}${remote}${RESET}"

  # Offer to open/create a PR
  local default
  default=$(default_branch)
  if [ "$open_pr" = "1" ] && [ "$branch" != "$default" ] && has_cmd gh; then
    _handle_pr "$branch"
  elif [ "$open_pr" = "1" ] && [ "$branch" != "$default" ]; then
    hint "Create a PR at your Git host, or install 'gh' for PR creation from the CLI."
  fi
}

_check_protected_branch() {
  local branch="$1" force="$2"
  # Default protected branch names (covers GitHub/GitLab/Bitbucket conventions)
  local protected_pattern="^(main|master|develop|dev|release|production|prod|staging)$"

  if [[ "$branch" =~ $protected_pattern ]]; then
    echo ""
    echo -e "${RED}${BOLD}⚠  PROTECTED BRANCH WARNING${RESET}"
    echo -e "${RED}  You are about to push directly to '${branch}'.${RESET}"
    echo -e "${YELLOW}  This bypasses code review and can affect production/shared history.${RESET}"
    echo ""
    if [ "$force" = "1" ]; then
      echo -e "${RED}  Force-pushing to a protected branch is especially dangerous.${RESET}"
      echo ""
    fi
    if ! confirm "Push directly to '${branch}'? (Consider using a feature branch + PR instead)"; then
      hint "Create a feature branch: g branch feat/my-change"
      return 1
    fi
  fi
}

_handle_pr() {
  local branch="$1"

  # Check if PR already exists
  local existing_pr
  existing_pr=$(gh pr view "$branch" --json url -q .url 2>/dev/null || echo "")

  if [ -n "$existing_pr" ]; then
    info "PR already open: $existing_pr"
    confirm "Open it in the browser?" && gh pr view "$branch" --web
  else
    if confirm "Create a pull request for '${branch}'?"; then
      run_cmd gh pr create --head "$branch" --fill
    fi
  fi
}

usage_push() {
  cat <<EOF
${BOLD}g push${RESET} — Push current branch to remote

${BOLD}USAGE${RESET}
  g push [flags]

${BOLD}FLAGS${RESET}
  -f, --force   Force push (uses --force-with-lease for safety)
  --no-pr       Skip PR creation prompt
  -h, --help    Show this help

${BOLD}EXAMPLES${RESET}
  g push            # Push, set upstream if needed, offer PR creation
  g push --force    # Force push (safe — uses --force-with-lease)
  g push --no-pr    # Push without PR prompt
EOF
}
