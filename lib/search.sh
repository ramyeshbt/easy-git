#!/usr/bin/env bash
# lib/search.sh — g search: Search commits, messages, and code changes
# Usage: g search <query> [--code] [--author <name>] [--since <date>] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_search() {
  require_git_repo_with_commits

  case "${1:-}" in
    -h|--help) usage_search; return 0 ;;
  esac

  local query=""
  local search_code=0
  local author=""
  local since=""
  local search_files=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)    usage_search; return 0 ;;
      -c|--code)    search_code=1; shift ;;
      -f|--files)   search_files=1; shift ;;
      --author)     shift; author="$1"; shift ;;
      --since)      shift; since="$1"; shift ;;
      *)            query="$1"; shift ;;
    esac
  done

  if [ -z "$query" ]; then
    query=$(prompt_input "Search for")
    [ -z "$query" ] && return 1
  fi

  # Prevent flag injection: reject values that start with -- (could inject git options)
  if [[ "$query" == --* ]]; then
    die "Search query cannot start with '--'. Did you mean to use a flag?"
  fi
  if [ -n "$author" ] && [[ "$author" == --* ]]; then
    die "Author value cannot start with '--'."
  fi
  if [ -n "$since" ] && [[ "$since" == --* ]]; then
    die "Since value cannot start with '--'."
  fi

  if [ "$search_files" = "1" ]; then
    search_in_files "$query"
    return $?
  fi

  if [ "$search_code" = "1" ]; then
    search_in_code "$query" "$author" "$since"
  else
    search_in_messages "$query" "$author" "$since"
  fi
}

# Search commit messages
search_in_messages() {
  local query="$1" author="$2" since="$3"

  header "Commits matching: '${query}' in message"

  local args=("--grep=$query" "--regexp-ignore-case")
  [ -n "$author" ] && args+=("--author=$author")
  [ -n "$since" ]  && args+=("--since=$since")

  local count=0
  while IFS= read -r line; do
    echo "$line"
    count=$((count + 1))
  done < <(git log --oneline "${args[@]}" 2>/dev/null | head -50)

  if [ "$count" = "0" ]; then
    warn "No commits found matching '${query}' in messages."
    hint "Try 'g search --code \"${query}\"' to search code changes instead."
    return 1
  fi

  hint "Showing up to 50 results. Use 'g log --grep \"${query}\"' for more options."
}

# Search code changes (git log -S / pickaxe)
search_in_code() {
  local query="$1" author="$2" since="$3"

  header "Commits that changed code containing: '${query}'"

  local args=("-S$query" "--all")
  [ -n "$author" ] && args+=("--author=$author")
  [ -n "$since" ]  && args+=("--since=$since")

  local format="%C(yellow)%h%C(reset) %C(cyan)%ad%C(reset) %C(green)%an%C(reset)  %s"
  local count=0
  while IFS= read -r line; do
    echo -e "  $line"
    count=$((count + 1))
  done < <(git log --date=short --pretty=format:"$format" "${args[@]}" 2>/dev/null | head -30)

  if [ "$count" = "0" ]; then
    warn "No commits found that changed code containing '${query}'."
    return 1
  fi
}

# Search filenames in git history
search_in_files() {
  local query="$1"

  header "Files matching '${query}' ever committed:"

  local count=0
  while IFS= read -r line; do
    echo -e "  ${CYAN}${line}${RESET}"
    count=$((count + 1))
  done < <(git log --all --full-history --name-only --pretty=format: -- "*${query}*" 2>/dev/null | grep -v "^$" | sort -u | head -30)

  if [ "$count" = "0" ]; then
    # Try current tree
    git ls-files "*${query}*" 2>/dev/null | while IFS= read -r line; do
      echo -e "  ${GREEN}${line}${RESET} ${DIM}(in current tree)${RESET}"
      count=$((count + 1))
    done
  fi

  if [ "$count" = "0" ]; then
    warn "No files found matching '${query}'."
    return 1
  fi
}

usage_search() {
  cat <<EOF
${BOLD}g search${RESET} — Search commit history

${BOLD}USAGE${RESET}
  g search <query> [flags]

${BOLD}FLAGS${RESET}
  -c, --code        Search commits that changed code containing <query>
  -f, --files       Search filenames in history
  --author <name>   Filter by commit author
  --since <date>    Filter commits after date (e.g. "2 weeks ago")
  -h, --help        Show this help

${BOLD}EXAMPLES${RESET}
  g search "fix auth"           # Search commit messages
  g search --code "parseUser"   # Find commits that touched parseUser
  g search --files "config"     # Find files named *config* in history
  g search "bug" --author Alice --since "1 month ago"
EOF
}
