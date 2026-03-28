#!/usr/bin/env bash
# lib/tag.sh — g tag: Create, list, delete, and push release tags
# Usage: g tag [<version>] [-l] [-d <tag>] [--push] [-h]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_tag() {
  require_git_repo_with_commits

  case "${1:-}" in
    -h|--help)    usage_tag; return 0 ;;
    -l|--list)    tag_list; return 0 ;;
    -d|--delete)  shift; tag_delete "$@"; return $? ;;
    "")           tag_list; return 0 ;;
    *)            tag_create "$@"; return $? ;;
  esac
}

tag_list() {
  local tag_count
  tag_count=$(git tag | wc -l | tr -d ' ')

  if [ "$tag_count" = "0" ]; then
    info "No tags yet."
    hint "Create one with: g tag v1.0.0"
    return 0
  fi

  header "Tags (${tag_count}):"
  # Show tags with their commit date and message
  git tag --sort=-version:refname | while IFS= read -r t; do
    local hash msg date
    hash=$(git rev-parse --short "${t}^{}" 2>/dev/null || git rev-parse --short "$t" 2>/dev/null)
    msg=$(git tag -l --format='%(contents:subject)' "$t" 2>/dev/null || echo "")
    date=$(git log -1 --pretty=format:"%ar" "${t}^{}" 2>/dev/null || echo "")
    if [ -n "$msg" ]; then
      echo -e "  ${CYAN}${t}${RESET}  ${DIM}${hash}  ${date}${RESET}  ${msg}"
    else
      echo -e "  ${CYAN}${t}${RESET}  ${DIM}${hash}  ${date}${RESET}"
    fi
  done
  echo ""
}

tag_create() {
  local version=""
  local message=""
  local push_tag=0
  local lightweight=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --push)       push_tag=1; shift ;;
      --light)      lightweight=1; shift ;;
      -m|--message) shift; message="$1"; shift ;;
      -*)           die "Unknown flag: $1" ;;
      *)            version="$1"; shift ;;
    esac
  done

  if [ -z "$version" ]; then
    # Suggest next version based on latest tag
    local latest
    latest=$(git tag --sort=-version:refname | head -1 2>/dev/null || echo "")
    local suggestion=""
    if [ -n "$latest" ]; then
      # Bump patch version: v1.2.3 → v1.2.4
      suggestion=$(echo "$latest" | awk -F. '{OFS="."; $NF=$NF+1; print}')
    else
      suggestion="v1.0.0"
    fi
    version=$(prompt_input "Tag name" "$suggestion")
    [ -z "$version" ] && { warn "Tag name is required."; return 1; }
  fi

  # Validate tag name — no spaces, shell-special chars, or leading dashes (flag injection)
  if [[ "$version" =~ [[:space:]] ]] || [[ "$version" =~ [\;\|\&\$\`\<\>] ]]; then
    die "Tag name '$version' contains invalid characters."
  fi
  if [[ "$version" == -* ]]; then
    die "Tag name must not start with '-' (would be interpreted as a flag)."
  fi

  # Check if tag already exists
  if git tag | grep -qxF "$version"; then
    die "Tag '$version' already exists. Use 'g tag -d $version' to delete it first."
  fi

  local current_hash current_branch
  current_hash=$(git rev-parse --short HEAD)
  current_branch=$(current_branch)

  echo ""
  echo -e "${BOLD}Creating tag:${RESET} ${CYAN}${version}${RESET}"
  echo -e "${BOLD}At commit:${RESET}   ${DIM}${current_hash}${RESET} on ${current_branch}"
  echo ""

  if [ "$lightweight" = "0" ]; then
    # Annotated tag (recommended — stores tagger, date, message)
    if [ -z "$message" ]; then
      message=$(prompt_input "Tag message" "Release $version")
    fi
    confirm "Create annotated tag '$version'?" || return 1
    run_cmd git tag -a -- "$version" -m "$message"
  else
    confirm "Create lightweight tag '$version'?" || return 1
    run_cmd git tag -- "$version"
  fi

  success "Tag ${BOLD}${version}${RESET} created at ${DIM}${current_hash}${RESET}"

  if [ "$push_tag" = "1" ]; then
    local remote
    remote=$(default_remote)
    run_cmd git push "$remote" -- "$version"
    success "Tag '${version}' pushed to ${remote}."
  else
    hint "Run 'g tag --push $version' or 'git push origin $version' to publish this tag."
  fi
}

tag_delete() {
  local version="${1:-}"
  local remote_too=0

  [ "$version" = "--remote" ] && { remote_too=1; shift; version="${1:-}"; }

  if [ -z "$version" ]; then
    local tags=()
    while IFS= read -r t; do tags+=("$t"); done < <(git tag --sort=-version:refname)
    [ "${#tags[@]}" -eq 0 ] && { warn "No tags to delete."; return 0; }
    version=$(fuzzy_select "Delete tag" "${tags[@]}")
    [ -z "$version" ] && return 1
  fi

  if ! git tag | grep -qxF "$version"; then
    die "Tag '$version' does not exist locally."
  fi

  confirm "Delete local tag '$version'?" || return 1
  run_cmd git tag -d -- "$version"
  success "Local tag '${version}' deleted."

  local remote
  remote=$(default_remote)
  if git ls-remote --tags "$remote" "$version" 2>/dev/null | grep -q "$version"; then
    if confirm "Also delete '$version' from remote '${remote}'?"; then
      run_cmd git push "$remote" --delete -- "$version"
      success "Remote tag '${version}' deleted."
    fi
  fi
}

usage_tag() {
  cat <<EOF
${BOLD}g tag${RESET} — Release tag management

${BOLD}USAGE${RESET}
  g tag                    # List all tags
  g tag <version>          # Create an annotated tag (recommended)
  g tag <version> --push   # Create and immediately push to remote
  g tag -d [version]       # Delete a tag (local + optional remote)

${BOLD}FLAGS${RESET}
  -l, --list           List all tags (default when no args)
  -d, --delete         Delete a tag
  --push               Push tag to remote after creating
  --light              Create a lightweight tag (no message)
  -m, --message <msg>  Tag message (skips interactive prompt)
  -h, --help           Show this help

${BOLD}EXAMPLES${RESET}
  g tag                    # List all tags
  g tag v1.2.0             # Create annotated tag
  g tag v1.2.0 --push      # Create + push
  g tag v1.2.0 -m "Hotfix release"
  g tag -d v1.1.0          # Delete old tag
EOF
}
