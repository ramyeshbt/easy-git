#!/usr/bin/env bash
# lib/blame.sh — g blame: Enhanced git blame with readable output
# Usage: g blame <file> [--line <n>] [--author <name>] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_blame() {
  require_git_repo_with_commits

  case "${1:-}" in
    -h|--help) usage_blame; return 0 ;;
    "")        usage_blame; return 0 ;;
  esac

  local file=""
  local line_range=""
  local author_filter=""
  local show_email=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)   usage_blame; return 0 ;;
      -l|--line)   shift; line_range="$1"; shift ;;
      --author)    shift; author_filter="$1"; shift ;;
      --email)     show_email=1; shift ;;
      --)          shift; file="$1"; shift ;;
      *)           file="$1"; shift ;;
    esac
  done

  if [ -z "$file" ]; then
    die "File path required. Usage: g blame <file>"
  fi

  if ! git ls-files --error-unmatch -- "$file" &>/dev/null 2>&1; then
    die "File '$file' is not tracked by git."
  fi

  header "Blame: $file"

  local args=()
  [ -n "$line_range" ] && args+=("-L" "$line_range")
  [ "$show_email" = "1" ] && args+=("-e")

  if has_cmd delta; then
    git blame --color-lines --color-by-age "${args[@]}" -- "$file" \
      | grep "${author_filter:-}" | delta --no-gitconfig --diff-highlight
  else
    # Formatted output: hash | date | author | line
    git blame --porcelain "${args[@]}" -- "$file" | _format_blame "$author_filter"
  fi
}

_format_blame() {
  local author_filter="${1:-}"
  local hash author date line_num content
  local current_hash="" current_author="" current_date=""

  while IFS= read -r line; do
    # Porcelain format: first line of a block is the hash + line numbers
    if [[ "$line" =~ ^([0-9a-f]{40})[[:space:]] ]]; then
      current_hash="${BASH_REMATCH[1]:0:8}"
    elif [[ "$line" =~ ^author[[:space:]](.+) ]]; then
      current_author="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^author-time[[:space:]](.+) ]]; then
      current_date=$(date -d "@${BASH_REMATCH[1]}" '+%Y-%m-%d' 2>/dev/null \
                   || date -r "${BASH_REMATCH[1]}" '+%Y-%m-%d' 2>/dev/null \
                   || echo "unknown")
    elif [[ "$line" =~ ^\t(.*)$ ]]; then
      content="${BASH_REMATCH[1]}"
      # Apply author filter
      if [ -z "$author_filter" ] || echo "$current_author" | grep -qi "$author_filter"; then
        printf "%b%-8s%b  %-10s  %-16s  %s\n" \
          "${CYAN}" "$current_hash" "${RESET}" \
          "$current_date" \
          "${current_author:0:16}" \
          "$content"
      fi
    fi
  done
}

usage_blame() {
  cat <<EOF
${BOLD}g blame${RESET} — See who wrote each line of a file

${BOLD}USAGE${RESET}
  g blame <file>                 # Blame entire file
  g blame <file> --line 10,20   # Only lines 10-20
  g blame <file> --author Alice  # Filter to Alice's lines

${BOLD}FLAGS${RESET}
  -l, --line <range>   Line range (e.g. 10,20 or 10,+5)
  --author <name>      Only show lines written by this author
  --email              Show email addresses
  -h, --help           Show this help

${BOLD}EXAMPLES${RESET}
  g blame src/auth.js              # Who wrote each line?
  g blame src/auth.js --line 40,60 # Focus on lines 40-60
  g blame README.md --author Alice  # Alice's contributions

${BOLD}TIP${RESET}
  Install 'delta' for syntax-highlighted blame output.
EOF
}
