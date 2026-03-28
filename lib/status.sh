#!/usr/bin/env bash
# lib/status.sh — g status: Enhanced git status with context-aware hints
# Usage: g status [-s] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_status() {
  require_git_repo

  case "${1:-}" in
    -h|--help) usage_status; return 0 ;;
    -s|--short) git status --short; return 0 ;;
  esac

  local branch remote ahead behind

  branch=$(current_branch)
  remote=$(default_remote)

  # ── Header ──────────────────────────────────────────────────────────────────
  echo ""
  if [ -z "$branch" ]; then
    echo -e "${YELLOW}⚠${RESET}  ${BOLD}Detached HEAD${RESET} at $(git rev-parse --short HEAD)"
  else
    echo -e "${BOLD}${BLUE} Branch:${RESET} ${BOLD}${branch}${RESET}"
  fi

  # ── Remote tracking info ─────────────────────────────────────────────────
  local upstream
  upstream=$(git for-each-ref --format='%(upstream:short)' "refs/heads/$branch" 2>/dev/null)

  if [ -n "$upstream" ]; then
    ahead=$(commits_ahead)
    behind=$(commits_behind)

    if [ "$ahead" = "0" ] && [ "$behind" = "0" ]; then
      echo -e "         ${GREEN}✓ Up to date${RESET} with ${DIM}${upstream}${RESET}"
    else
      [ "$behind" -gt 0 ] && echo -e "         ${YELLOW}↓ ${behind} behind${RESET} ${DIM}${upstream}${RESET} — run ${CYAN}g sync${RESET}"
      [ "$ahead"  -gt 0 ] && echo -e "         ${CYAN}↑ ${ahead} ahead${RESET}  ${DIM}${upstream}${RESET} — run ${CYAN}g push${RESET} when ready"
    fi
  else
    echo -e "         ${DIM}No remote tracking branch — run ${CYAN}g push${RESET} to publish${RESET}"
  fi

  echo ""

  # ── Staged changes ──────────────────────────────────────────────────────
  local staged
  staged=$(git diff --cached --name-status 2>/dev/null)
  if [ -n "$staged" ]; then
    echo -e "${GREEN}${BOLD}Staged for commit:${RESET}"
    echo "$staged" | while IFS=$'\t' read -r status file; do
      local icon label
      case "$status" in
        A*) icon="${GREEN}+${RESET}"; label="new file  " ;;
        M*) icon="${GREEN}~${RESET}"; label="modified  " ;;
        D*) icon="${RED}-${RESET}";   label="deleted   " ;;
        R*) icon="${CYAN}→${RESET}"; label="renamed   " ;;
        C*) icon="${CYAN}C${RESET}"; label="copied    " ;;
        *)  icon="${YELLOW}?${RESET}"; label="$status         " ;;
      esac
      echo -e "  ${icon}  ${label} ${file}"
    done
    echo ""
  fi

  # ── Unstaged changes ────────────────────────────────────────────────────
  local unstaged
  unstaged=$(git diff --name-status 2>/dev/null)
  if [ -n "$unstaged" ]; then
    echo -e "${YELLOW}${BOLD}Changes not staged:${RESET}"
    echo "$unstaged" | while IFS=$'\t' read -r status file; do
      local icon label
      case "$status" in
        M*) icon="${YELLOW}~${RESET}"; label="modified  " ;;
        D*) icon="${RED}-${RESET}";    label="deleted   " ;;
        *)  icon="${YELLOW}?${RESET}"; label="$status         " ;;
      esac
      echo -e "  ${icon}  ${label} ${file}"
    done
    echo ""
  fi

  # ── Untracked files ──────────────────────────────────────────────────────
  local untracked
  untracked=$(git ls-files --others --exclude-standard 2>/dev/null | head -10)
  if [ -n "$untracked" ]; then
    echo -e "${DIM}${BOLD}Untracked files:${RESET}"
    echo "$untracked" | while IFS= read -r file; do
      echo -e "  ${DIM}?  untracked  ${file}${RESET}"
    done
    local total_untracked
    total_untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
    if [ "$total_untracked" -gt 10 ]; then
      hint "  ...and $((total_untracked - 10)) more. Add to .gitignore if unwanted."
    fi
    echo ""
  fi

  # ── Clean state ──────────────────────────────────────────────────────────
  if [ -z "$staged" ] && [ -z "$unstaged" ] && [ -z "$untracked" ]; then
    echo -e "  ${GREEN}✓ Working tree clean${RESET}"
    echo ""
  fi

  # ── Contextual hints ────────────────────────────────────────────────────
  _status_hints "$staged" "$unstaged" "$untracked"
}

_status_hints() {
  local staged="$1" unstaged="$2" untracked="$3"

  if [ -n "$staged" ]; then
    hint "To commit staged:   g commit"
    hint "To unstage all:     git restore --staged ."
  fi
  if [ -n "$unstaged" ]; then
    hint "To stage changes:   git add <file>  OR  git add -A"
    hint "To discard changes: git restore <file>"
  fi
  if [ -n "$untracked" ]; then
    hint "To track a file:    git add <file>"
    hint "To ignore a file:   echo '<file>' >> .gitignore"
  fi

  # Stash hint
  local stash_count
  stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
  if [ "$stash_count" -gt 0 ]; then
    hint "You have ${stash_count} stashed change(s) — run 'g stash list' to see them."
  fi
}

usage_status() {
  cat <<EOF
${BOLD}g status${RESET} — Enhanced git status

${BOLD}USAGE${RESET}
  g status [flags]

${BOLD}FLAGS${RESET}
  -s, --short    Compact porcelain output
  -h, --help     Show this help
EOF
}
