#!/usr/bin/env bash
# lib/diff.sh — g diff: Enhanced diff with staged/unstaged/branch modes
# Usage: g diff [--staged] [--branch <name>] [<file>] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_diff() {
  require_git_repo

  local staged=0
  local branch=""
  local file=""
  local stat_only=0
  local extra_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)        usage_diff; return 0 ;;
      -s|--staged|--cached) staged=1; shift ;;
      -b|--branch)      shift; branch="$1"; shift ;;
      --stat)           stat_only=1; shift ;;
      --)               shift; file="$1"; shift ;;
      -*)               extra_args+=("$1"); shift ;;
      *)
        # If it looks like a file that exists, treat it as a file
        if [ -e "$1" ] || git ls-files --error-unmatch -- "$1" &>/dev/null 2>&1; then
          file="$1"
        else
          branch="$1"
        fi
        shift
        ;;
    esac
  done

  # Decide pager: use delta if available, else git's own pager
  local pager=""
  has_cmd delta && pager="delta"

  if [ -n "$branch" ]; then
    _diff_branch "$branch" "$file" "$stat_only" "${extra_args[@]}"
  elif [ "$staged" = "1" ]; then
    _diff_staged "$file" "$stat_only" "${extra_args[@]}"
  else
    _diff_working "$file" "$stat_only" "${extra_args[@]}"
  fi
}

_diff_working() {
  local file="$1" stat_only="$2"; shift 2
  local title="Unstaged changes"
  [ -n "$file" ] && title="Changes in: $file"
  header "$title"

  if [ "$stat_only" = "1" ]; then
    git diff --stat -- ${file:+"$file"} "$@"
  else
    if has_cmd delta; then
      git diff -- ${file:+"$file"} "$@" | delta
    else
      git diff -- ${file:+"$file"} "$@"
    fi
  fi

  local count
  count=$(git diff --name-only -- ${file:+"$file"} 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" = "0" ]; then
    info "No unstaged changes."
    hint "Use 'g diff --staged' to see staged changes."
  fi
}

_diff_staged() {
  local file="$1" stat_only="$2"; shift 2
  header "Staged changes (ready to commit)"

  if [ "$stat_only" = "1" ]; then
    git diff --cached --stat -- ${file:+"$file"} "$@"
  else
    if has_cmd delta; then
      git diff --cached -- ${file:+"$file"} "$@" | delta
    else
      git diff --cached -- ${file:+"$file"} "$@"
    fi
  fi

  local count
  count=$(git diff --cached --name-only -- ${file:+"$file"} 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" = "0" ]; then
    info "Nothing staged."
    hint "Use 'git add <file>' to stage changes, then run 'g diff --staged'."
  fi
}

_diff_branch() {
  local branch="$1" file="$2" stat_only="$3"; shift 3
  local current
  current=$(current_branch)
  header "Diff: $current vs $branch"

  if [ "$stat_only" = "1" ]; then
    git diff --stat "${branch}...HEAD" -- ${file:+"$file"} "$@"
  else
    if has_cmd delta; then
      git diff "${branch}...HEAD" -- ${file:+"$file"} "$@" | delta
    else
      git diff "${branch}...HEAD" -- ${file:+"$file"} "$@"
    fi
  fi
}

usage_diff() {
  cat <<EOF
${BOLD}g diff${RESET} — Enhanced diff viewer

${BOLD}USAGE${RESET}
  g diff                      # Unstaged changes
  g diff --staged             # Staged changes (what will be committed)
  g diff <branch>             # Compare current branch vs another branch
  g diff -- <file>            # Diff a specific file
  g diff --stat               # Show only summary stats

${BOLD}FLAGS${RESET}
  -s, --staged    Show staged (cached) changes
  -b, --branch    Compare with a branch
  --stat          Summary stats only (no line-by-line)
  -h, --help      Show this help

${BOLD}EXAMPLES${RESET}
  g diff                      # What changed since last commit
  g diff --staged             # What's about to be committed
  g diff main                 # How my branch differs from main
  g diff -- src/auth.js       # Only changes in auth.js
  g diff --stat               # Quick overview of changed files

${BOLD}TIP${RESET}
  Install 'delta' for syntax-highlighted diffs: brew install git-delta
EOF
}
