#!/usr/bin/env bash
# lib/ignore.sh — g ignore: Add entries to .gitignore with smart suggestions
# Usage: g ignore [<pattern>] [--list] [--undo] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_ignore() {
  require_git_repo

  case "${1:-}" in
    -h|--help)   usage_ignore; return 0 ;;
    -l|--list)   ignore_list; return 0 ;;
    --undo)      shift; ignore_undo "$@" ;;
    "")          ignore_interactive ;;
    *)           ignore_add "$@" ;;
  esac
}

ignore_add() {
  local gitignore
  gitignore="$(git_root)/.gitignore"
  local added=0

  for pattern in "$@"; do
    # Check if already ignored
    if git check-ignore -q -- "$pattern" 2>/dev/null; then
      info "'${pattern}' is already ignored."
      continue
    fi

    # Check if already in .gitignore literally
    if [ -f "$gitignore" ] && grep -qxF "$pattern" "$gitignore" 2>/dev/null; then
      info "'${pattern}' is already in .gitignore."
      continue
    fi

    # Warn if the file is already tracked
    if git ls-files --error-unmatch -- "$pattern" &>/dev/null 2>&1; then
      warn "'${pattern}' is already tracked by git."
      warn "Adding it to .gitignore won't remove it from the repo."
      if confirm "Also untrack it (git rm --cached)?"; then
        run_cmd git rm --cached -- "$pattern"
        success "Untracked '$pattern' from git (file stays on disk)."
      fi
    fi

    echo "$pattern" >> "$gitignore"
    success "Added '${BOLD}${pattern}${RESET}' to .gitignore"
    added=$((added + 1))
  done

  if [ "$added" -gt 0 ]; then
    hint "Commit the .gitignore change: g commit"
  fi
}

ignore_interactive() {
  local gitignore
  gitignore="$(git_root)/.gitignore"

  header "Add to .gitignore"
  echo ""

  # Show untracked files as suggestions
  local untracked=()
  while IFS= read -r f; do
    untracked+=("$f")
  done < <(git ls-files --others --exclude-standard 2>/dev/null | head -20)

  if [ "${#untracked[@]}" -gt 0 ]; then
    echo -e "${DIM}Untracked files (common candidates):${RESET}"
    for f in "${untracked[@]}"; do
      echo -e "  ${YELLOW}?${RESET}  $f"
    done
    echo ""
  fi

  local pattern
  pattern=$(prompt_input "Pattern to ignore (e.g. *.log, node_modules/, .env)")
  [ -z "$pattern" ] && return 1

  ignore_add "$pattern"
}

ignore_list() {
  local gitignore
  gitignore="$(git_root)/.gitignore"

  if [ ! -f "$gitignore" ]; then
    info "No .gitignore file yet."
    hint "Run 'g ignore <pattern>' to create one."
    return 0
  fi

  header ".gitignore entries:"
  grep -v "^#" "$gitignore" | grep -v "^$" | while IFS= read -r line; do
    echo -e "  ${DIM}${line}${RESET}"
  done
  echo ""
  hint "File: $gitignore"
}

ignore_undo() {
  local pattern="${1:-}"
  local gitignore
  gitignore="$(git_root)/.gitignore"

  if [ ! -f "$gitignore" ]; then
    warn "No .gitignore file found."
    return 1
  fi

  if [ -z "$pattern" ]; then
    # Pick from existing entries
    local entries=()
    while IFS= read -r line; do
      [[ "$line" =~ ^#.*$ ]] && continue
      [ -z "$line" ] && continue
      entries+=("$line")
    done < "$gitignore"

    [ "${#entries[@]}" -eq 0 ] && { warn "No entries in .gitignore."; return 0; }
    pattern=$(fuzzy_select "Remove from .gitignore" "${entries[@]}")
    [ -z "$pattern" ] && return 1
  fi

  if ! grep -qxF "$pattern" "$gitignore" 2>/dev/null; then
    warn "'${pattern}' not found in .gitignore."
    return 1
  fi

  # Safe removal using temp file
  local tmp
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  grep -vxF "$pattern" "$gitignore" > "$tmp" || true
  mv "$tmp" "$gitignore"
  trap - EXIT

  success "Removed '${pattern}' from .gitignore"
  hint "The file may now appear as untracked. Run 'g status' to check."
}

usage_ignore() {
  cat <<EOF
${BOLD}g ignore${RESET} — Add entries to .gitignore

${BOLD}USAGE${RESET}
  g ignore                     # Interactive — pick from untracked files
  g ignore <pattern>           # Add a specific pattern
  g ignore -l                  # List current .gitignore entries
  g ignore --undo [pattern]    # Remove an entry from .gitignore

${BOLD}EXAMPLES${RESET}
  g ignore                     # Interactive picker
  g ignore .env                # Ignore .env file
  g ignore "*.log"             # Ignore all .log files
  g ignore node_modules/       # Ignore node_modules directory
  g ignore -l                  # See all ignore rules
  g ignore --undo .env         # Stop ignoring .env

${BOLD}COMMON PATTERNS${RESET}
  *.log              Log files
  *.env, .env.*      Environment/secret files
  node_modules/      Node.js dependencies
  __pycache__/       Python cache
  .DS_Store          macOS metadata
  dist/, build/      Build output
  *.sqlite, *.db     Local databases
EOF
}
