#!/usr/bin/env bash
# lib/core.sh — Shared colors, helpers, and utilities for all g subcommands
# All lib/*.sh files source this and only this.

# ─── Colors (only when stdout is a TTY) ──────────────────────────────────────
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  MAGENTA='\033[0;35m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' BOLD='' DIM='' RESET=''
fi

# ─── Output helpers ───────────────────────────────────────────────────────────
success() { echo -e "${GREEN}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $*"; }
error()   { echo -e "${RED}✗${RESET} $*" >&2; }
info()    { echo -e "${CYAN}→${RESET} $*"; }
hint()    { echo -e "${DIM}  $*${RESET}"; }
header()  { echo -e "\n${BOLD}${BLUE}$*${RESET}"; }
die()     { error "$*"; exit 1; }

# ─── Git guards ───────────────────────────────────────────────────────────────
require_git_repo() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    die "Not inside a git repository. Run 'git init' or 'cd' into a repo."
  fi
}

require_git_repo_with_commits() {
  require_git_repo
  if ! git rev-parse HEAD &>/dev/null; then
    die "Repository has no commits yet. Make an initial commit first."
  fi
}

# ─── Git helpers ─────────────────────────────────────────────────────────────
# Get current branch name (or empty string in detached HEAD)
current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || echo ""
}

# Get the default remote branch (main or master)
default_branch() {
  local remote_default
  remote_default=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  if [ -n "$remote_default" ]; then
    echo "$remote_default"
    return
  fi
  # fallback: check if main or master exists
  if git show-ref --verify --quiet refs/heads/main; then
    echo "main"
  elif git show-ref --verify --quiet refs/heads/master; then
    echo "master"
  else
    echo "main"  # best guess
  fi
}

# Get the remote name (defaults to 'origin')
default_remote() {
  git remote | head -1 || echo "origin"
}

# Is the working tree dirty?
is_dirty() {
  ! git diff --quiet || ! git diff --cached --quiet
}

# Is there anything staged?
has_staged() {
  ! git diff --cached --quiet
}

# Number of commits ahead of origin
commits_ahead() {
  local branch remote_branch
  branch=$(current_branch)
  remote_branch=$(git for-each-ref --format='%(upstream:short)' "refs/heads/$branch" 2>/dev/null)
  if [ -z "$remote_branch" ]; then
    echo "0"
    return
  fi
  git rev-list --count "${remote_branch}..HEAD" 2>/dev/null || echo "0"
}

# Number of commits behind origin
commits_behind() {
  local branch remote_branch
  branch=$(current_branch)
  remote_branch=$(git for-each-ref --format='%(upstream:short)' "refs/heads/$branch" 2>/dev/null)
  if [ -z "$remote_branch" ]; then
    echo "0"
    return
  fi
  git rev-list --count "HEAD..${remote_branch}" 2>/dev/null || echo "0"
}

# ─── Interactive helpers ──────────────────────────────────────────────────────
# Ask user a yes/no question
confirm() {
  local prompt="$1"
  local answer
  printf "%b" "${YELLOW}?${RESET} ${prompt} [y/N] "
  # Use /dev/tty when interactive; fall back to stdin for pipes/CI
  if [ -t 0 ]; then
    read -r answer </dev/tty
  else
    read -r answer
  fi
  case "$answer" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# Fuzzy select from a list (uses fzf if available, fallback to numbered list)
# Usage: selected=$(fuzzy_select "Pick a branch" item1 item2 item3)
fuzzy_select() {
  local prompt="$1"
  shift
  local items=("$@")

  if command -v fzf &>/dev/null && [ -t 0 ]; then
    printf '%s\n' "${items[@]}" | fzf --prompt="$prompt > " --height=40% --reverse --no-info
    return
  fi

  # Fallback: numbered list
  local i
  for i in "${!items[@]}"; do
    printf "  ${CYAN}%2d${RESET}) %s\n" "$((i+1))" "${items[$i]}"
  done
  printf "%b" "${YELLOW}?${RESET} ${prompt} [1-${#items[@]}]: "
  local choice
  read -r choice </dev/tty
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
    echo "${items[$((choice-1))]}"
  fi
}

# Prompt for text input with a default
prompt_input() {
  local prompt="$1"
  local default="${2:-}"
  local value
  if [ -n "$default" ]; then
    printf "%b" "${CYAN}?${RESET} ${prompt} [${DIM}${default}${RESET}]: "
  else
    printf "%b" "${CYAN}?${RESET} ${prompt}: "
  fi
  read -r value </dev/tty
  echo "${value:-$default}"
}

# ─── Dry-run support ─────────────────────────────────────────────────────────
# Set G_DRY_RUN=1 to preview commands without running them
run_cmd() {
  if [ "${G_DRY_RUN:-0}" = "1" ]; then
    echo -e "${DIM}[dry-run]${RESET} $*"
  else
    "$@"
  fi
}

# ─── Misc utilities ───────────────────────────────────────────────────────────
# Truncate string to max length
truncate_str() {
  local str="$1"
  local max="${2:-60}"
  if [ "${#str}" -gt "$max" ]; then
    echo "${str:0:$((max-3))}..."
  else
    echo "$str"
  fi
}

# Check if a command exists
has_cmd() {
  command -v "$1" &>/dev/null
}

# Get git root directory
git_root() {
  git rev-parse --show-toplevel 2>/dev/null
}
