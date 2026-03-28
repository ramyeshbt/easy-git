#!/usr/bin/env bash
# lib/log.sh — g log: Beautiful colored graph log
# Usage: g log [--short] [--full] [-n <count>] [--author <name>] [--since <date>] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_log() {
  require_git_repo_with_commits

  local mode="default"
  local count=20
  local extra_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)         usage_log; return 0 ;;
      -s|--short)        mode="short"; shift ;;
      -f|--full)         mode="full"; shift ;;
      -b|--branch-only)  mode="branch"; shift ;;
      -n|--count)        shift; count="$1"; shift ;;
      --author)          shift; extra_args+=("--author=$1"); shift ;;
      --since)           shift; extra_args+=("--since=$1"); shift ;;
      --until)           shift; extra_args+=("--until=$1"); shift ;;
      --grep)            shift; extra_args+=("--grep=$1"); shift ;;
      --all)             extra_args+=("--all"); shift ;;
      --file|-F)         shift; extra_args+=("--follow" "--" "$1"); shift ;;  # GAP-20: file history
      *)                 extra_args+=("$1"); shift ;;
    esac
  done

  case "$mode" in
    short)   log_short "$count" "${extra_args[@]}" ;;
    full)    log_full "$count" "${extra_args[@]}" ;;
    branch)  log_branch "$count" "${extra_args[@]}" ;;
    *)       log_default "$count" "${extra_args[@]}" ;;
  esac
}

log_default() {
  local count="$1"; shift
  local format="%C(yellow)%h%C(reset) %C(cyan)%ad%C(reset) %C(green)%<(12,trunc)%an%C(reset)  %s%C(red)%d%C(reset)"
  git log \
    --graph \
    --date=format:'%Y-%m-%d' \
    --pretty=format:"$format" \
    -n "$count" \
    "$@"
  echo ""
  _log_hint "$count" "$@"
}

log_short() {
  local count="$1"; shift
  git log \
    --oneline \
    --graph \
    -n "$count" \
    "$@"
  _log_hint "$count" "$@"
}

log_full() {
  local count="$1"; shift
  git log \
    --stat \
    --date=relative \
    -n "$count" \
    "$@"
}

log_branch() {
  local count="$1"; shift
  local base
  base=$(default_branch)
  local current
  current=$(current_branch)
  echo -e "${BOLD}Commits on '${current}' not in '${base}':${RESET}\n"
  git log \
    --graph \
    --oneline \
    "${base}..HEAD" \
    "$@"
}

_log_hint() {
  local count="$1"
  local total
  total=$(git rev-list --count HEAD 2>/dev/null || echo 0)
  if [ "$total" -gt "$count" ]; then
    hint "Showing $count of $total commits. Use '-n <count>' for more, or '--full' for details."
  fi
}

usage_log() {
  cat <<EOF
${BOLD}g log${RESET} — Pretty colored commit log

${BOLD}USAGE${RESET}
  g log [flags]

${BOLD}FLAGS${RESET}
  -s, --short           One-line per commit with graph
  -f, --full            Full commit details with file stats
  -b, --branch-only     Only commits on current branch (not in main)
  -n <count>            Number of commits to show (default: 20)
  --author <name>       Filter by author
  --since <date>        Filter commits after date (e.g. "2 weeks ago")
  --grep <pattern>      Filter by commit message
  --all                 Show all branches
  --file, -F <path>     Show only commits that touched a specific file (follows renames)
  -h, --help            Show this help

${BOLD}EXAMPLES${RESET}
  g log                         # Default graph log (last 20)
  g log -s                      # Compact one-liners
  g log -b                      # Only my branch's commits
  g log -n 50 --author Alice    # Last 50 by Alice
  g log --since "1 week ago"    # This week's commits
  g log --grep "feat:"          # Find feature commits
  g log --all                   # All branches
  g log --file src/auth.js      # History of one file (follows renames)
EOF
}
