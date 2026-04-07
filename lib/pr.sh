#!/usr/bin/env bash
# lib/pr.sh — g pr: Open or create pull requests
# Usage: g pr [create|open|list|status] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_pr() {
  require_git_repo_with_commits

  case "${1:-}" in
    -h|--help)     usage_pr; return 0 ;;
    create|c)      shift; pr_create "$@" ;;
    open|o)        shift; pr_open "$@" ;;
    list|l)        pr_list ;;
    status|s)      pr_status ;;
    checkout|co)   shift; pr_checkout "$@" ;;
    "")            pr_default ;;
    *)             die "Unknown pr command: '$1'. Use 'g pr --help'." ;;
  esac
}

# Default: if PR exists, open it; otherwise offer to create
pr_default() {
  local branch
  branch=$(current_branch)
  local default
  default=$(default_branch)

  if [ "$branch" = "$default" ]; then
    pr_list
    return 0
  fi

  if ! has_cmd gh; then
    die "The 'gh' CLI is required for PR commands. Install it from https://cli.github.com"
  fi

  local existing_url
  existing_url=$(gh pr view "$branch" --json url -q .url 2>/dev/null || echo "")

  if [ -n "$existing_url" ]; then
    pr_status
  else
    pr_create
  fi
}

pr_create() {
  if ! has_cmd gh; then
    die "The 'gh' CLI is required. Install it from https://cli.github.com"
  fi

  local branch default title body
  branch=$(current_branch)
  default=$(default_branch)

  if [ "$branch" = "$default" ]; then
    die "You are on the default branch '${default}'. Switch to a feature branch first."
  fi

  # Check if PR already exists
  local existing
  existing=$(gh pr view "$branch" --json url -q .url 2>/dev/null || echo "")
  if [ -n "$existing" ]; then
    warn "PR already exists for '${branch}': ${existing}"
    confirm "Open it in browser?" && gh pr view "$branch" --web
    return 0
  fi

  # Build title from branch name or last commit
  local auto_title
  auto_title=$(git log -1 --pretty=format:"%s" 2>/dev/null)

  header "Create pull request for '${branch}'"

  title=$(prompt_input "PR title" "$auto_title")
  [ -z "$title" ] && { warn "Title is required."; return 1; }

  echo -e "\n${CYAN}?${RESET} PR description (optional, press Enter to skip, Ctrl+D when done):"
  local body_lines=()
  if [ -t 0 ]; then
    while IFS= read -r line </dev/tty; do
      [ -z "$line" ] && break
      body_lines+=("$line")
    done 2>/dev/null || true
  else
    while IFS= read -r line; do
      [ -z "$line" ] && break
      body_lines+=("$line")
    done
  fi
  body=$(printf '%s\n' "${body_lines[@]}")

  local draft=0
  confirm "Create as draft PR?" && draft=1

  echo ""

  local args=("pr" "create" "--head" "$branch" "--title" "$title")
  [ -n "$body" ] && args+=("--body" "$body")
  [ "$draft" = "1" ] && args+=("--draft")

  run_cmd gh "${args[@]}"
}

pr_open() {
  if ! has_cmd gh; then
    die "The 'gh' CLI is required. Install it from https://cli.github.com"
  fi

  local branch="${1:-$(current_branch)}"
  run_cmd gh pr view "$branch" --web
}

pr_list() {
  if ! has_cmd gh; then
    die "The 'gh' CLI is required. Install it from https://cli.github.com"
  fi

  gh pr list --limit 20
}

pr_status() {
  if ! has_cmd gh; then
    die "The 'gh' CLI is required. Install it from https://cli.github.com"
  fi

  local branch
  branch=$(current_branch)

  gh pr view "$branch" 2>/dev/null || {
    warn "No open PR found for branch '${branch}'."
    hint "Run 'g pr create' to open one."
    return 1
  }
}

pr_checkout() {
  if ! has_cmd gh; then
    die "The 'gh' CLI is required. Install it from https://cli.github.com"
  fi

  local pr_ref="${1:-}"

  if [ -z "$pr_ref" ]; then
    # List open PRs and let user pick
    header "Open pull requests:"
    local prs=()
    while IFS= read -r line; do
      prs+=("$line")
    done < <(gh pr list --limit 30 --json number,title,headRefName \
      --template '{{range .}}#{{.number}}  {{.headRefName}}  {{.title}}{{"\n"}}{{end}}' 2>/dev/null)

    if [ "${#prs[@]}" -eq 0 ]; then
      warn "No open PRs found."
      return 1
    fi

    local selected
    selected=$(fuzzy_select "Checkout PR" "${prs[@]}")
    [ -z "$selected" ] && return 1

    # Extract PR number from selection (starts with #NNN)
    pr_ref=$(echo "$selected" | grep -oE '^#[0-9]+' | tr -d '#')
    [ -z "$pr_ref" ] && die "Could not parse PR number from selection."
  fi

  run_cmd gh pr checkout "$pr_ref"
  success "Checked out PR #${pr_ref}"
}

usage_pr() {
  cat <<EOF
${BOLD}g pr${RESET} — Pull request management (requires gh CLI)

${BOLD}USAGE${RESET}
  g pr               # Auto: show PR if exists, or offer to create
  g pr create        # Create a new PR for current branch
  g pr open          # Open current branch's PR in browser
  g pr list          # List open PRs in this repo
  g pr status        # Show status of current branch's PR
  g pr checkout [N]  # Checkout a PR by number (or pick interactively)

${BOLD}REQUIREMENTS${RESET}
  gh CLI: https://cli.github.com (brew install gh / scoop install gh)

${BOLD}EXAMPLES${RESET}
  g pr               # Smart default
  g pr create        # Interactive PR creation
  g pr open          # Open PR in browser
  g pr list          # See all open PRs
EOF
}
