#!/usr/bin/env bash
# lib/init.sh — g init: Guided repository setup wizard
# Usage: g init [directory] [-h]
#
# Covers every prerequisite for working with git:
#   identity · default branch · .gitignore template · README · initial commit

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

# ── Module globals (set by wizard steps, applied during execution) ────────────
_INIT_LOCAL_NAME=""    # user.name  to apply locally (empty = global already set)
_INIT_LOCAL_EMAIL=""   # user.email to apply locally
_INIT_BRANCH="main"    # chosen default branch name
_INIT_TEMPLATE=""      # .gitignore template (empty = skip)

# ── Entry point ───────────────────────────────────────────────────────────────
main_init() {
  case "${1:-}" in
    -h|--help) usage_init; return 0 ;;
  esac

  local target_dir="${1:-.}"

  header "g init — Repository Setup Wizard"
  echo ""
  echo -e "  ${DIM}Sets up git identity, branch, .gitignore, README, and initial commit.${RESET}"
  echo ""

  # ── Resolve target directory ────────────────────────────────────────────────
  if [ "$target_dir" != "." ]; then
    if [ ! -d "$target_dir" ]; then
      confirm "Directory '${target_dir}' does not exist. Create it?" \
        || { info "Cancelled."; return 0; }
      if [ "${G_DRY_RUN:-0}" = "1" ]; then
        echo -e "${DIM}[dry-run]${RESET} mkdir -p $target_dir"
      else
        mkdir -p "$target_dir" || die "Cannot create directory '$target_dir'"
        success "Created '$target_dir'"
      fi
    fi
    cd "$target_dir" || die "Cannot enter '$target_dir'"
  fi

  local project_name
  project_name=$(basename "$(pwd)")

  # ── Guard: already a git repo? ──────────────────────────────────────────────
  local has_commits=0
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    if git rev-parse HEAD &>/dev/null; then
      has_commits=1
      warn "This directory already has a git repository with commits."
    else
      warn "This directory already has a git repository (no commits yet)."
    fi
    confirm "Continue and re-configure?" || { info "Cancelled."; return 0; }
    echo ""
  fi

  info "Project: ${BOLD}${project_name}${RESET}   Path: ${DIM}$(pwd)${RESET}"
  echo ""
  echo -e "${DIM}  ────────────────────────────────────────────────────${RESET}"

  # ── Run git init ─────────────────────────────────────────────────────────────
  run_cmd git init -q
  echo ""

  # ── Step 1: Identity ────────────────────────────────────────────────────────
  _INIT_LOCAL_NAME=""
  _INIT_LOCAL_EMAIL=""
  _init_step_identity

  # ── Step 2: Default branch ──────────────────────────────────────────────────
  _INIT_BRANCH="main"
  _init_step_branch "$has_commits"

  # ── Step 3: .gitignore template ─────────────────────────────────────────────
  _INIT_TEMPLATE=""
  _init_step_gitignore

  # ── Step 4: README ──────────────────────────────────────────────────────────
  _init_step_readme "$project_name"

  # ── Step 5: Initial commit ──────────────────────────────────────────────────
  _init_step_commit

  # ── Next steps ──────────────────────────────────────────────────────────────
  _init_show_next_steps
}

# ── Step 1: Git identity ─────────────────────────────────────────────────────
_init_step_identity() {
  echo ""
  echo -e "  ${BOLD}${BLUE}[1/4] Git Identity${RESET}"
  echo -e "  ${DIM}Your name and email are recorded in every commit you make.${RESET}"
  echo ""

  local gname gemail
  gname=$(git config --global user.name  2>/dev/null || echo "")
  gemail=$(git config --global user.email 2>/dev/null || echo "")

  if [ -n "$gname" ] && [ -n "$gemail" ]; then
    info "Global identity: ${BOLD}${gname}${RESET} <${CYAN}${gemail}${RESET}>"
    hint "Press Enter to keep, or type a new value to override for this repo only."
    echo ""
  else
    echo -e "  ${YELLOW}⚠${RESET}  No global git identity found."
    echo -e "  ${DIM}  You must set a name and email before you can make commits.${RESET}"
    echo ""
  fi

  local name email
  name=$(prompt_input  "Full name"  "$gname")
  email=$(prompt_input "Email"      "$gemail")

  [ -z "$name"  ] && die "Name is required to make commits."
  [ -z "$email" ] && die "Email is required to make commits."

  if [ -z "$gname" ] || [ -z "$gemail" ]; then
    # No global config at all — ask where to save
    echo ""
    echo -e "  ${CYAN}1${RESET}) Save globally  ${DIM}— applies to all repos on this machine (recommended)${RESET}"
    echo -e "  ${CYAN}2${RESET}) Save locally   ${DIM}— applies to this repo only${RESET}"
    echo ""
    printf "%b" "  ${YELLOW}?${RESET} Scope [1-2, default=1]: "
    local scope_choice
    if [ -t 0 ]; then read -r scope_choice </dev/tty; else read -r scope_choice; fi

    if [ "${scope_choice:-1}" = "2" ]; then
      _INIT_LOCAL_NAME="$name"
      _INIT_LOCAL_EMAIL="$email"
      hint "Identity will be saved to this repository's local config."
    else
      git config --global user.name  "$name"
      git config --global user.email "$email"
      success "Global identity saved: ${BOLD}${name}${RESET} <${CYAN}${email}${RESET}>"
    fi
  elif [ "$name" != "$gname" ] || [ "$email" != "$gemail" ]; then
    # Changed from global — apply locally only (don't overwrite global)
    _INIT_LOCAL_NAME="$name"
    _INIT_LOCAL_EMAIL="$email"
    hint "Differs from global — will be set as local config for this repo."
  fi
  # else: same as global — nothing to do

  # Apply local config immediately (git init has already run)
  if [ -n "$_INIT_LOCAL_NAME" ]; then
    git config user.name  "$_INIT_LOCAL_NAME"
    git config user.email "$_INIT_LOCAL_EMAIL"
    success "Local identity set: ${BOLD}${_INIT_LOCAL_NAME}${RESET} <${CYAN}${_INIT_LOCAL_EMAIL}${RESET}>"
  fi
  echo ""
}

# ── Step 2: Default branch ────────────────────────────────────────────────────
# $1 = 1 if repo already has commits (need git branch -m), 0 otherwise
_init_step_branch() {
  local has_commits="${1:-0}"

  echo -e "  ${BOLD}${BLUE}[2/4] Default Branch${RESET}"
  echo -e "  ${DIM}The branch where your first commit lands. New projects use 'main'.${RESET}"
  echo ""
  echo -e "    ${CYAN}1${RESET}) main    ${DIM}(recommended — GitHub/GitLab/Bitbucket default)${RESET}"
  echo -e "    ${CYAN}2${RESET}) master  ${DIM}(legacy — classic git default)${RESET}"
  echo -e "    ${CYAN}3${RESET}) custom"
  echo ""
  printf "%b" "  ${YELLOW}?${RESET} Choose [1-3, default=1]: "

  local choice
  if [ -t 0 ]; then read -r choice </dev/tty; else read -r choice; fi

  case "${choice:-1}" in
    1|"")   _INIT_BRANCH="main" ;;
    2)      _INIT_BRANCH="master" ;;
    3)
      printf "%b" "  ${CYAN}?${RESET} Branch name [main]: "
      local custom
      if [ -t 0 ]; then read -r custom </dev/tty; else read -r custom; fi
      # Sanitize: alphanumeric, dash, underscore only — no leading dash
      custom=$(echo "${custom:-main}" | sed 's/[[:space:]]/-/g' | sed 's/[^a-zA-Z0-9_-]//g')
      custom="${custom#-}"
      _INIT_BRANCH="${custom:-main}"
      ;;
    *)
      # User typed a branch name directly
      local cleaned
      cleaned=$(echo "$choice" | sed 's/[[:space:]]/-/g' | sed 's/[^a-zA-Z0-9_-]//g')
      cleaned="${cleaned#-}"
      _INIT_BRANCH="${cleaned:-main}"
      ;;
  esac

  # Set the branch name
  if [ "$has_commits" = "1" ]; then
    # Repo has commits — rename existing branch if different
    local current
    current=$(current_branch)
    if [ -n "$current" ] && [ "$current" != "$_INIT_BRANCH" ]; then
      run_cmd git branch -m -- "$current" "$_INIT_BRANCH"
    fi
  else
    # No commits yet — set via symbolic-ref (works on all git versions)
    git symbolic-ref HEAD "refs/heads/$_INIT_BRANCH" 2>/dev/null || true
  fi

  info "Default branch: ${BOLD}${_INIT_BRANCH}${RESET}"
  echo ""
}

# ── Step 3: .gitignore ────────────────────────────────────────────────────────
_init_step_gitignore() {
  echo -e "  ${BOLD}${BLUE}[3/4] .gitignore Template${RESET}"
  echo -e "  ${DIM}Keeps build artifacts, secrets, and editor files out of your commits.${RESET}"
  echo ""

  if [ -f ".gitignore" ]; then
    warn ".gitignore already exists."
    if ! confirm "  Overwrite it with a template?"; then
      info "Keeping existing .gitignore"
      echo ""
      return 0
    fi
    echo ""
  fi

  echo -e "    ${CYAN}1${RESET}) Node.js   ${DIM}— node_modules, dist, .env ...${RESET}"
  echo -e "    ${CYAN}2${RESET}) Python    ${DIM}— __pycache__, venv, .egg-info ...${RESET}"
  echo -e "    ${CYAN}3${RESET}) Go        ${DIM}— binaries, vendor/ ...${RESET}"
  echo -e "    ${CYAN}4${RESET}) Rust      ${DIM}— target/, debug builds ...${RESET}"
  echo -e "    ${CYAN}5${RESET}) Java      ${DIM}— *.class, target/, .gradle/ ...${RESET}"
  echo -e "    ${CYAN}6${RESET}) Ruby      ${DIM}— .bundle/, vendor/bundle/ ...${RESET}"
  echo -e "    ${CYAN}7${RESET}) C/C++     ${DIM}— *.o, *.a, build/ ...${RESET}"
  echo -e "    ${CYAN}8${RESET}) PHP       ${DIM}— vendor/, composer.lock ...${RESET}"
  echo -e "    ${CYAN}9${RESET}) Generic   ${DIM}— build artifacts + OS files (recommended default)${RESET}"
  echo -e "    ${CYAN}0${RESET}) None      ${DIM}— skip${RESET}"
  echo ""
  printf "%b" "  ${YELLOW}?${RESET} Choose template [0-9, default=9]: "

  local choice
  if [ -t 0 ]; then read -r choice </dev/tty; else read -r choice; fi

  case "${choice:-9}" in
    0)      _INIT_TEMPLATE="" ;;
    1)      _INIT_TEMPLATE="Node.js" ;;
    2)      _INIT_TEMPLATE="Python" ;;
    3)      _INIT_TEMPLATE="Go" ;;
    4)      _INIT_TEMPLATE="Rust" ;;
    5)      _INIT_TEMPLATE="Java" ;;
    6)      _INIT_TEMPLATE="Ruby" ;;
    7)      _INIT_TEMPLATE="C/C++" ;;
    8)      _INIT_TEMPLATE="PHP" ;;
    9|"")   _INIT_TEMPLATE="Generic" ;;
    *)      _INIT_TEMPLATE="Generic" ;;
  esac

  if [ -z "$_INIT_TEMPLATE" ]; then
    info "Skipping .gitignore"
  else
    if [ "${G_DRY_RUN:-0}" = "1" ]; then
      echo -e "${DIM}[dry-run]${RESET} would write .gitignore (${_INIT_TEMPLATE} template)"
    else
      _write_gitignore "$_INIT_TEMPLATE"
      success ".gitignore created (${_INIT_TEMPLATE} template)"
    fi
  fi
  echo ""
}

# ── Step 4: README ────────────────────────────────────────────────────────────
_init_step_readme() {
  local project_name="$1"

  echo -e "  ${BOLD}${BLUE}[4/4] README.md${RESET}"
  echo -e "  ${DIM}Describes your project to contributors and visitors.${RESET}"
  echo ""

  if [ -f "README.md" ]; then
    info "README.md already exists — skipping."
    echo ""
    return 0
  fi

  if ! confirm "  Create a README.md?"; then
    echo ""
    return 0
  fi

  local desc
  desc=$(prompt_input "  One-line description" "A new project")

  if [ "${G_DRY_RUN:-0}" = "1" ]; then
    echo -e "${DIM}[dry-run]${RESET} would create README.md for '${project_name}'"
  else
    # Write README — use printf to avoid heredoc variable expansion issues
    printf '# %s\n\n%s\n\n## Getting Started\n\n```bash\ngit clone <your-repo-url>\ncd %s\n```\n\n## Contributing\n\n1. Create a branch: `g branch feat/your-feature`\n2. Commit your changes: `g commit`\n3. Push: `g push`\n' \
      "$project_name" "$desc" "$project_name" > README.md
    success "Created README.md"
  fi
  echo ""
}

# ── Step 5: Initial commit ────────────────────────────────────────────────────
_init_step_commit() {
  echo -e "${DIM}  ────────────────────────────────────────────────────${RESET}"
  echo ""
  header "Initial Commit"
  echo ""

  local file_count
  file_count=$(git status --porcelain 2>/dev/null | wc -l | awk '{print $1}')

  if [ "$file_count" -eq 0 ]; then
    info "No files to commit yet."
    if confirm "Create an empty initial commit?"; then
      run_cmd git commit --allow-empty -m "chore: initial commit"
      success "Empty initial commit created."
    else
      hint "Run 'g commit' when you're ready to make your first commit."
    fi
    return 0
  fi

  info "${BOLD}${file_count}${RESET} file(s) ready to stage:"
  git status --short 2>/dev/null | head -15 | sed 's/^/    /'
  [ "$file_count" -gt 15 ] && hint "    ... and $((file_count - 15)) more"
  echo ""

  if confirm "Stage all files and create initial commit?"; then
    local msg
    msg=$(prompt_input "Commit message" "chore: initial commit")
    run_cmd git add -A
    run_cmd git commit -m "$msg"
    success "Initial commit created."
  else
    hint "Run 'g commit' when you're ready."
  fi
  echo ""
}

# ── Next steps ────────────────────────────────────────────────────────────────
_init_show_next_steps() {
  local identity
  identity="$(git config user.name 2>/dev/null || echo "?") <$(git config user.email 2>/dev/null || echo "?")>"

  header "You're all set!"
  echo ""
  echo -e "  ${GREEN}✓${RESET}  Repository:  ${BOLD}$(pwd)${RESET}"
  echo -e "  ${GREEN}✓${RESET}  Branch:      ${CYAN}${_INIT_BRANCH}${RESET}"
  echo -e "  ${GREEN}✓${RESET}  Identity:    ${DIM}${identity}${RESET}"
  [ -n "$_INIT_TEMPLATE" ] && echo -e "  ${GREEN}✓${RESET}  .gitignore:  ${DIM}${_INIT_TEMPLATE} template${RESET}"
  echo ""
  echo -e "  ${BOLD}Connect to a remote:${RESET}"
  echo -e "    ${DIM}# GitHub — easiest (requires gh CLI):${RESET}"
  echo -e "      ${CYAN}gh repo create${RESET}"
  echo ""
  echo -e "    ${DIM}# Or add an existing remote manually:${RESET}"
  echo -e "      git remote add origin <url>"
  echo -e "      ${CYAN}g push${RESET}"
  echo ""
  echo -e "  ${BOLD}Common next commands:${RESET}"
  echo -e "    ${CYAN}g status${RESET}            — see what's in your repo"
  echo -e "    ${CYAN}g branch feat/x${RESET}     — start a feature branch"
  echo -e "    ${CYAN}g commit${RESET}             — make your next commit"
  echo -e "    ${CYAN}g --doctor${RESET}           — verify your full setup"
  echo ""
}

# ── .gitignore template writer (non-interactive — testable independently) ─────
# Usage: _write_gitignore <template-name>
# Writes template content + universal secrets/OS section to .gitignore
_write_gitignore() {
  local template="$1"

  case "$template" in
    "Node.js")
cat > .gitignore << 'GITIGNORE_EOF'
# ── Node.js ───────────────────────────────────────────────────────────────────
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*
.pnpm-store/

# Build output
dist/
build/
.next/
.nuxt/
out/
.svelte-kit/

# Cache
.cache/
.parcel-cache/
.eslintcache
.stylelintcache
coverage/
.nyc_output/
.turbo/

# Runtime
pids/
*.pid
*.seed
*.log
GITIGNORE_EOF
    ;;
    "Python")
cat > .gitignore << 'GITIGNORE_EOF'
# ── Python ────────────────────────────────────────────────────────────────────
__pycache__/
*.py[cod]
*$py.class
*.pyo
*.pyd

# Virtual environments
venv/
.venv/
env/
ENV/
.python-version

# Distribution / packaging
*.egg
*.egg-info/
dist/
build/
.eggs/
wheels/

# Testing & type checking
.pytest_cache/
.coverage
htmlcov/
.tox/
.nox/
.mypy_cache/
.ruff_cache/
.hypothesis/

# Jupyter
.ipynb_checkpoints/
GITIGNORE_EOF
    ;;
    "Go")
cat > .gitignore << 'GITIGNORE_EOF'
# ── Go ────────────────────────────────────────────────────────────────────────
# Binaries
*.exe
*.exe~
*.dll
*.so
*.dylib
/bin/

# Test binary, built with `go test -c`
*.test
*.out

# Dependency directory
vendor/

# Go workspace
go.work
go.work.sum
GITIGNORE_EOF
    ;;
    "Rust")
cat > .gitignore << 'GITIGNORE_EOF'
# ── Rust ──────────────────────────────────────────────────────────────────────
/target/
**/*.rs.bk

# Binaries
*.exe
*.dll
*.so
*.dylib
GITIGNORE_EOF
    ;;
    "Java")
cat > .gitignore << 'GITIGNORE_EOF'
# ── Java ──────────────────────────────────────────────────────────────────────
*.class
*.jar
*.war
*.ear
*.nar
hs_err_pid*
replay_pid*

# Build
target/
build/
out/

# Gradle
.gradle/
gradle-app.setting
!gradle-wrapper.jar
!gradle-wrapper.properties

# Maven
pom.xml.tag
pom.xml.releaseBackup
pom.xml.versionsBackup
release.properties

# IDE
.idea/
*.iml
*.iws
*.ipr
.classpath
.project
.settings/
GITIGNORE_EOF
    ;;
    "Ruby")
cat > .gitignore << 'GITIGNORE_EOF'
# ── Ruby ──────────────────────────────────────────────────────────────────────
*.gem
*.rbc
/.config
/coverage/
/InstalledFiles
/pkg/
/spec/reports/
/test/tmp/
/tmp/

# Bundler
.bundle/
vendor/bundle/
Gemfile.lock

# Rails
/log/
/db/*.sqlite3
/public/system
/public/assets
/storage/
/config/master.key
.byebug_history
GITIGNORE_EOF
    ;;
    "C/C++")
cat > .gitignore << 'GITIGNORE_EOF'
# ── C / C++ ───────────────────────────────────────────────────────────────────
# Prerequisites
*.d

# Object files
*.o
*.ko
*.obj

# Static and dynamic libraries
*.a
*.lib
*.la
*.lo
*.so
*.so.*
*.dylib
*.dll

# Executables
*.exe
*.out
*.app
*.i*86
*.x86_64

# CMake
CMakeLists.txt.user
CMakeCache.txt
CMakeFiles/
cmake_install.cmake
build/
cmake-build-*/
GITIGNORE_EOF
    ;;
    "PHP")
cat > .gitignore << 'GITIGNORE_EOF'
# ── PHP ───────────────────────────────────────────────────────────────────────
/vendor/
composer.phar
.phpunit.result.cache
.phpunit.cache/
.php-cs-fixer.cache
.php_cs.cache

# Laravel
/bootstrap/cache/
Homestead.json
Homestead.yaml
npm-debug.log
yarn-error.log

# Symfony
/var/
/public/bundles/
GITIGNORE_EOF
    ;;
    *)
      # Generic — safe default for any project
cat > .gitignore << 'GITIGNORE_EOF'
# ── Generic ───────────────────────────────────────────────────────────────────
# Build artifacts
build/
dist/
out/
bin/
*.o
*.a
*.so
*.dll
*.exe

# Logs and temp
*.log
logs/
tmp/
temp/
*.tmp
*.bak
GITIGNORE_EOF
    ;;
  esac

  # ── Appended to every template: secrets + OS/editor files ─────────────────
cat >> .gitignore << 'GITIGNORE_EOF'

# ── Secrets — never commit these ─────────────────────────────────────────────
.env
.env.local
.env.*.local
.env.production
*.pem
*.key
*.p12
*.pfx
*.cer
*.crt
secrets.*
credentials.*
*_rsa
*_dsa
*_ed25519
*_ecdsa
.netrc
.vault-pass
terraform.tfvars
.aws/credentials
.docker/config.json
.npmrc
.kube/config

# ── OS / Editor ───────────────────────────────────────────────────────────────
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
Thumbs.db
Desktop.ini
.idea/
.vscode/
*.sublime-workspace
*.swp
*.swo
*~
GITIGNORE_EOF
}

# ── Help ──────────────────────────────────────────────────────────────────────
usage_init() {
  cat <<EOF
${BOLD}g init${RESET} — Guided repository setup wizard

${BOLD}USAGE${RESET}
  g init                   # Set up git in the current directory
  g init <directory>       # Create directory and initialize it

${BOLD}THE WIZARD COVERS${RESET}
  1. ${BOLD}Git identity${RESET}       — user.name and user.email (global or local scope)
  2. ${BOLD}Default branch${RESET}     — main (recommended), master, or custom name
  3. ${BOLD}.gitignore${RESET}         — language template + built-in secrets protection
  4. ${BOLD}README.md${RESET}          — project title and description starter
  5. ${BOLD}Initial commit${RESET}     — stage all files and create first commit

${BOLD}.GITIGNORE TEMPLATES${RESET}
  Node.js  Python  Go  Rust  Java  Ruby  C/C++  PHP  Generic

  All templates include a secrets section that blocks .env, *.pem, *.key,
  private keys, and credentials files from being accidentally committed.

${BOLD}EXAMPLES${RESET}
  g init                   # Wizard in current directory
  g init my-project        # Create my-project/ and run wizard
  g init --help            # Show this help

${BOLD}AFTER INIT${RESET}
  g status                 # See repo state
  g branch feat/x          # Create a feature branch
  g commit                 # Make your first commit
  g push                   # Push to remote
  g --doctor               # Verify full setup
EOF
}
