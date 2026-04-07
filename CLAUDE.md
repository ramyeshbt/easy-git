# CLAUDE.md — Easy Git Tool
> Inspired by Boris Cherny's Claude Code tips + best practices from CLAUDE-2.md.
> **Rule:** Any time Claude does something wrong, add a rule here so it doesn't happen again.
> Commit this file. Everyone on the team can update it.

**Authors:** ramyeshbt · Claude Sonnet 4.6 (Anthropic)
**License:** Apache 2.0 — see [LICENSE](LICENSE)

---

## CRITICAL RULES — READ FIRST

| # | Rule | Why |
|---|------|-----|
| 1 | Always **Plan Mode** before adding new git subcommands | Git operations are destructive — plan first |
| 2 | Run `bash tests/run_tests.sh` after every meaningful change | Regressions in git tooling are painful |
| 3 | **Never hardcode paths** — use `$HOME`, `$GIT_ROOT`, relative paths | Portability across machines |
| 4 | **Never run destructive git commands** (reset --hard, push --force) without explicit `--force` flag from user | Safety first |
| 5 | Every subcommand must have a `--help` / `-h` flag | Discoverability |
| 6 | All user-facing output must use color codes from `lib/core.sh` | Consistency |
| 7 | **Never use `${var,}` or `${var^^}`** for case conversion — bash 4.0+ only, macOS ships bash 3.2. Use `tr '[:upper:]' '[:lower:]'` instead | Cross-platform (found in commit.sh:169 by bash-reviewer agent) |
| 8 | Never declare "done" without running `bash tests/run_tests.sh` | Quality gate |
| 9 | Prefer `git` plumbing commands over porcelain where reliability matters | Stability |
| 10 | After every correction: *"Update CLAUDE.md so this doesn't happen again."* | Compounding improvement |
| 11 | **`git checkout -b` must NOT use `--` between `-b` and the branch name** — use `git checkout -b "$name"` (not `git checkout -b -- "$name"`). Use `--` only before file paths, not branch names after `-b`. Reject leading-dash names with a `case` guard instead. | `git checkout -b -- name` makes git treat `--` as the branch name and `name` as the start-point (broken in git 2.23+) |
| 12 | **Always add `|| true`** after `grep -v` in pipelines under `set -euo pipefail` | grep -v returns 1 when all lines match — kills script |
| 13 | **Always `trap 'rm -f "$tmp"' EXIT`** when using `mktemp` | Prevents temp file leaks on error |
| 14 | **New subcommands that rewrite history** (squash, rebase) must warn the user and require confirm() | History rewrites on shared branches break teammates |
| 15 | **`g conflict`** must handle all three in-progress states: merge, rebase, cherry-pick | Missing a state leaves users stranded |
| 16 | **`g push` must warn before pushing to protected branches** (main, master, develop, release, production, staging) | Direct pushes bypass PR review; added `_check_protected_branch()` in push.sh |
| 17 | **`confirm()` must fall back to stdin when not a TTY** — use `if [ -t 0 ]; then read </dev/tty; else read; fi` | Tests pipe `echo "y" \| func` to stdin; reading from `/dev/tty` silently ignores the pipe |
| 18 | **`run_tests.sh` must guard `output=$(bash test_file)` with `set +e` / `set -e`** | Under `set -euo pipefail`, a failing test subshell exits the runner before any other suite runs |
| 19 | **Test helpers `assert_fails` / `assert_exits_ok` must run commands in a subshell `( "$@" )`** | `die()` calls `exit 1`; without a subshell that kills the entire test script mid-run |
| 20 | **Portability regex checks must exclude comment lines** — pipe grep output through `grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'` | Inline comments explaining bash 4+ patterns (e.g. `# ${var,} is bash 4+`) trigger false positives |
| 21 | **ShellCheck exclusions needed for this project** — always use `-e SC1090,SC1091,SC2034` on `lib/*.sh` and `bin/g`; add `-e SC2164` for test files | SC1090/91: dynamic source paths; SC2034: cross-file vars; SC2164: cd in test scripts |
| 22 | **Color variables must use `$'\033[...]'` (ANSI-C quoting), NOT `'\033[...]'`** — single-quoted strings store literal `\033` chars; `echo -e` handles them but `cat <<EOF` heredocs do NOT, causing raw `\033[0;31m` to appear in `g --help` output on Linux | Affects any script using `cat <<EOF` with `${BOLD}`, `${CYAN}` etc. (bin/g show_help, all usage_* functions) |
| 23 | **Never use `${var:-stash@{0}}` or similar complex literals with nested `{}`** inside `${...:-default}` expansion — bash may consume the inner `}` as the outer closer, appending a stray `}` to the value. Use `[ -z "$var" ] && var='stash@{0}'` instead | Found in stash.sh: `"${1:-stash@{0}}"` produced `stash@{0}}` making the stash@{N} validation regex always fail |
| 24 | **`git tag -a` flags order: always `-m "$msg" --` before the tag name** — `git tag -a -- v1.0.0 -m "msg"` treats `-m` as a positional arg after `--`, causing "fatal: too many arguments" | `git tag -a -m "$message" -- "$version"` is correct |
| 25 | **When a command takes an identifier (stash ref, tag name, commit hash), always show available options on validation error** — use a helper like `_stash_ref_error()` that prints the list before dying | UX: user gets stuck without knowing valid values; test with `g stash drop "name"` |
| 26 | **Every `read` from `/dev/tty` must have a TTY guard** — use `if [ -t 0 ]; then read -r val </dev/tty; else read -r val; fi` in ALL interactive-input functions (`prompt_input`, `fuzzy_select`, any future helpers). `confirm()` already does this — keep all reads consistent. | `/dev/tty` crashes in CI, VS Code integrated terminal, and piped input with "No such device or address" |
| 27 | **Non-interactive subcommand forms must support `--yes`/`-y`** and auto-apply it when `stdin` is not a TTY (`[ ! -t 0 ] && yes=1`). Don't add a `confirm()` gate that blocks forever on a command the user already typed explicitly. | `g undo commit` hung indefinitely in non-TTY sandboxes because `read` blocked on empty stdin |

---

## TABLE OF CONTENTS
1. [Project Overview](#1-project-overview)
2. [Tech Stack & Tooling](#2-tech-stack--tooling)
3. [Development Workflow](#3-development-workflow)
4. [Code Style & Conventions](#4-code-style--conventions)
5. [Architecture & Structure](#5-architecture--structure)
6. [Adding New Subcommands](#6-adding-new-subcommands)
7. [Testing Strategy](#7-testing-strategy)
8. [Verification Protocol](#8-verification-protocol)
9. [Subcommand Reference](#9-subcommand-reference)
10. [Plan Mode Protocol](#10-plan-mode-protocol)
11. [Parallel Execution Strategy](#11-parallel-execution-strategy)
12. [Subagent Patterns](#12-subagent-patterns)
13. [Hooks Configuration](#13-hooks-configuration)
14. [Permissions & Safety](#14-permissions--safety)
15. [Slash Commands](#15-slash-commands)
16. [Agents](#16-agents)
17. [Security Hardening — Audit Findings & Fixes](#17-security-hardening--audit-findings--fixes)
18. [CI / GitHub Actions Learnings](#18-ci--github-actions-learnings)
19. [Bug Fixing Protocol](#19-bug-fixing-protocol-was-18)
20. [Long-Running Task Handling](#20-long-running-task-handling)
21. [Terminal & Environment](#21-terminal--environment)
22. [DO NOTs — Anti-Patterns](#22-do-nots--anti-patterns)
23. [Workflow Coverage Audit](#23-workflow-coverage-audit)
24. [Project-Specific Rules](#24-project-specific-rules)

---

## 1. PROJECT OVERVIEW

```
Project:      easy-git (g)
Description:  A bash-based CLI wrapper around git that makes everyday git workflows
              dramatically faster and more intuitive. Replaces 10-20 memorized git
              commands with one smart `g` command with intelligent defaults.
Repo:         e:/programming/git_tool
Primary Lang: Bash (POSIX-compatible where possible, bash 3.2+)
Entry point:  bin/g
Install:      bash install.sh
```

### Goals for Claude
- Understand every script in `lib/` before modifying it.
- Prefer adding to existing files over creating new ones.
- Every change must be testable — add a test in `tests/` for every new feature.
- When in doubt about a git behavior, check `man git-<cmd>` or test in a temp repo.
- Keep the UX simple: a beginner should understand every output line.

### What This Tool Solves
| Pain Point | Solution |
|-----------|----------|
| `git add -A && git commit -m "..."` every time | `g commit` — interactive staged + message |
| Forgetting `-u origin HEAD` on first push | `g push` — auto-sets upstream |
| Merge conflicts when switching branches | `g sync` — stash, pull, pop automatically |
| Losing work with wrong undo | `g undo` — shows what it will do before doing it |
| Long unreadable `git log --oneline --graph` flags | `g log` — beautiful output, zero flags needed |
| Stale merged branches piling up | `g clean` — one command removes all merged branches |
| "Which branch was that ticket on?" | `g search` — searches commits, messages, and code |

---

## 2. TECH STACK & TOOLING

### Language & Runtime
```
Bash: 3.2+ (macOS ships 3.2; Linux typically 5.x)
Required external tools: git (2.0+), sed, awk, grep, sort, head
Optional (gracefully degraded): fzf, gh (GitHub CLI), delta (git diff pager)
```

### Key Scripts
```bash
# Install the tool (adds bin/ to PATH via ~/.bashrc or ~/.zshrc)
bash install.sh

# Run all tests
bash tests/run_tests.sh

# Run specific test file
bash tests/test_commit.sh

# Test a subcommand manually
./bin/g status
./bin/g commit
./bin/g log --short
```

### Dependency Check
```bash
# The tool runs this automatically on first use
./bin/g --doctor
```

---

## 3. DEVELOPMENT WORKFLOW

### Standard Loop (per feature/fix)
```
1. Enter Plan Mode — plan new subcommand or change.
2. Read the relevant lib/*.sh file before touching it.
3. Make change → add/update test in tests/.
4. Run: bash tests/run_tests.sh
5. Test manually in a real git repo.
6. Commit with Conventional Commits format.
```

### Git Conventions (for this repo itself)
```bash
feat: add `g pr` subcommand for GitHub PR creation
fix: handle detached HEAD state in g-sync
chore: update install.sh for zsh compatibility
docs: add examples to g-search help text
test: add regression test for empty repo edge case
```

### Branch Strategy
```
main           — stable, always installable
feature/<name> — new subcommand or major feature
fix/<name>     — bug fixes
```

---

## 4. CODE STYLE & CONVENTIONS

### Bash Style
- Use `#!/usr/bin/env bash` shebang on all scripts
- `set -euo pipefail` at the top of every script
- Quote ALL variable expansions: `"$var"` not `$var`
- Use `local` for all function-local variables
- Functions named `snake_case`; constants named `SCREAMING_SNAKE`
- Max function length: ~40 lines — extract helpers if longer
- No hardcoded strings for colors — use `$RED`, `$GREEN` etc from `lib/core.sh`
- Always check return codes for git commands

### Output Conventions
```bash
# Success
echo -e "${GREEN}✓${RESET} Committed: $message"

# Warning
echo -e "${YELLOW}⚠${RESET} No staged files — staging all tracked changes"

# Error (to stderr)
echo -e "${RED}✗${RESET} Not a git repository" >&2

# Info/hint
echo -e "${CYAN}→${RESET} Run 'g push' to push your changes"
```

### Error Handling
```bash
# Always guard git commands
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  error "Not inside a git repository"
  exit 1
fi

# Confirm destructive actions
confirm "This will delete branch '$branch'. Continue?" || exit 0
```

---

## 5. ARCHITECTURE & STRUCTURE

```
git_tool/
├── CLAUDE.md                   # This file
├── install.sh                  # Installer — adds bin/ to PATH
├── uninstall.sh                # Removes PATH entry + symlinks
├── bin/
│   └── g                       # Main entry point — routes subcommands
├── lib/
│   ├── core.sh                 # Colors, helpers, shared functions (ALL scripts source this)
│   ├── commit.sh               # g commit — smart interactive commit + secret detection
│   ├── push.sh                 # g push — push with auto-upstream
│   ├── sync.sh                 # g sync — sync with main/master
│   ├── branch.sh               # g branch — create/switch/delete branches
│   ├── diff.sh                 # g diff — enhanced diff (unstaged/staged/vs-branch)
│   ├── log.sh                  # g log — pretty colored graph log
│   ├── status.sh               # g status — enhanced status with hints
│   ├── undo.sh                 # g undo — safe undo with preview
│   ├── revert.sh               # g revert — safe revert (creates new revert commit)
│   ├── squash.sh               # g squash — squash WIP commits before PR
│   ├── tag.sh                  # g tag — release tag management
│   ├── conflict.sh             # g conflict — guided conflict resolution
│   ├── stash.sh                # g stash — named stash management
│   ├── clean.sh                # g clean — remove merged/gone branches
│   ├── search.sh               # g search — search commits + code
│   ├── blame.sh                # g blame — enhanced git blame
│   ├── reflog.sh               # g reflog — reflog viewer + recovery wizard
│   ├── ignore.sh               # g ignore — .gitignore management
│   └── pr.sh                   # g pr — open/create pull requests
├── tests/
│   ├── run_tests.sh            # Test runner — runs all test files
│   ├── helpers.sh              # Test utilities (setup_repo, assert_*)
│   ├── test_core.sh            # Tests for core utilities
│   ├── test_commit.sh          # Tests for g commit
│   ├── test_branch.sh          # Tests for g branch
│   ├── test_sync.sh            # Tests for g sync
│   ├── test_undo.sh            # Tests for g undo
│   ├── test_clean.sh           # Tests for g clean
│   └── test_security.sh        # Security regression tests
└── .claude/
    ├── commands/
    │   ├── new-subcommand.md   # Scaffold a new subcommand
    │   ├── add-test.md         # Add tests for a subcommand
    │   └── release.md          # Release checklist
    ├── agents/
    │   ├── git-analyzer.md     # Analyzes git repo state for debugging
    │   └── bash-reviewer.md    # Reviews bash scripts for safety/portability
    └── settings.json
```

### Key Design Decisions
- **Single entry point** (`bin/g`) routes to `lib/<cmd>.sh` — easy to add new subcommands
- **lib/core.sh is the only shared dependency** — every lib/*.sh sources it and nothing else
- **No global state** — each subcommand is a standalone function call
- **Graceful degradation** — tool works without fzf/gh, just with fewer features
- **Dry-run support** — `G_DRY_RUN=1 g sync` shows what would happen without doing it

---

## 6. ADDING NEW SUBCOMMANDS

### Checklist
```
1. Create lib/<name>.sh with a main_<name>() function
2. Source lib/core.sh at the top
3. Add --help / -h handling
4. Register in bin/g dispatch table
5. Add tests/test_<name>.sh
6. Update §9 Subcommand Reference in this file
```

### Template
```bash
#!/usr/bin/env bash
# lib/mycommand.sh — g mycommand: short description
# Usage: g mycommand [options]

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

main_mycommand() {
  require_git_repo

  case "${1:-}" in
    -h|--help) usage_mycommand; return 0 ;;
  esac

  # ... implementation
  success "Done!"
}

usage_mycommand() {
  echo "Usage: g mycommand [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help    Show this help"
}
```

---

## 7. TESTING STRATEGY

### Test Structure
```
tests/helpers.sh     — setup_repo(), assert_eq(), assert_contains(), assert_fails()
tests/test_*.sh      — one file per subcommand
tests/run_tests.sh   — discovers and runs all test_*.sh files
```

### Running Tests
```bash
bash tests/run_tests.sh                # all tests
bash tests/test_commit.sh              # single file
VERBOSE=1 bash tests/run_tests.sh      # verbose output
```

### Testing Rules
- Every new subcommand needs tests
- Every bug fix needs a regression test
- Tests use temporary git repos (created in /tmp, cleaned up after)
- Tests must not touch the real repo or user's git config
- Tests must pass on both macOS (bash 3.2) and Linux (bash 5+)

---

## 8. VERIFICATION PROTOCOL

```bash
# 1. Run all tests
bash tests/run_tests.sh

# 2. Test manually in a temp repo
cd /tmp && rm -rf test-repo && mkdir test-repo && cd test-repo
git init && git commit --allow-empty -m "init"
g status
g log
g commit

# 3. Check for bash syntax errors
bash -n bin/g
for f in lib/*.sh; do bash -n "$f"; done

# 4. Check portability (no bash 4+ features without guard)
grep -n "declare -A\|readarray\|mapfile" lib/*.sh  # these need bash 4+

# 5. Check for hardcoded paths
grep -n '"/home\|"/Users\|C:\\' lib/*.sh bin/g
```

---

## 9. SUBCOMMAND REFERENCE

### Setup
| Command | Short | Description |
|---------|-------|-------------|
| `g init` | `g i` | Guided wizard: identity · branch · .gitignore · README · initial commit |

### Daily Workflow
| Command | Short | Description |
|---------|-------|-------------|
| `g commit` | `g c` | Interactive conventional commit builder |
| `g push` | `g p` | Push with auto-upstream + optional PR creation |
| `g sync` | `g sy` | Sync with main: stash→fetch→rebase→pop |
| `g status` | `g s` | Enhanced status with context-aware hints |
| `g diff` | `g d` | Diff: unstaged / staged (`--staged`) / vs-branch |
| `g log` | `g l` | Pretty colored graph log |

### Branching & History
| Command | Short | Description |
|---------|-------|-------------|
| `g branch` | `g b` | Create/switch/delete branches with fuzzy search |
| `g squash` | `g sq` | Squash WIP commits into one before merging |
| `g revert` | `g rv` | Undo a pushed commit (safe — new revert commit) |
| `g tag` | `g t` | Create/list/delete/push release tags |

### Fixes & Recovery
| Command | Short | Description |
|---------|-------|-------------|
| `g undo` | `g u` | Safe undo — commit / push / file (with preview) |
| `g conflict` | `g cf` | Guided merge conflict resolution |
| `g reflog` | `g rl` | Show reflog; recover lost commits or branches |

### Research & Housekeeping
| Command | Short | Description |
|---------|-------|-------------|
| `g search` | `g sr` | Search commit messages and code changes |
| `g blame` | `g bl` | Who wrote each line of a file |
| `g stash` | | Named stash: save/pop/list/drop/show |
| `g clean` | `g cl` | Remove merged + gone branches |
| `g ignore` | `g gi` | Add/manage .gitignore entries |
| `g pr` | | Open or create pull requests (requires gh) |
| `g --doctor` | | Check dependencies and git config |

---

## 10. PLAN MODE PROTOCOL

Enter Plan Mode (shift+tab ×2) before:
- Adding a new subcommand
- Modifying git operations that touch history (undo, sync, clean)
- Changing install.sh or anything that modifies the user's shell config

### Plan Template
```markdown
## Goal
<What subcommand/feature to add or fix>

## Affected Files
<lib/*.sh, tests/*.sh, bin/g>

## Approach
1. <Step 1>
2. <Step 2>

## Edge Cases
- Empty repo (no commits)
- Detached HEAD
- No remote configured
- Dirty working tree

## Verification
bash tests/run_tests.sh && bash -n bin/g
```

---

## 11. PARALLEL EXECUTION STRATEGY

### When to Parallelise
- Testing while writing a new subcommand in another session
- Reviewing existing scripts while adding a new one
- Running `bash tests/run_tests.sh` in a background tab while iterating

### Session Naming Convention
```bash
claude --name "feat-new-subcommand"   # Tab 1: Feature work
claude --name "test-runner"           # Tab 2: Test watching
claude --name "bash-review"           # Tab 3: Script review
```

### Parallel Testing
```bash
# Run tests in the background while continuing development
VERBOSE=1 bash tests/run_tests.sh &
```

---

## 12. SUBAGENT PATTERNS

### When to Use Subagents
- Append **"use subagents"** to any task where parallel research helps
- Offload bash script review to the `bash-reviewer` agent
- Offload git repo diagnosis to the `git-analyzer` agent

### Standard Subagents (`.claude/agents/`)
| Agent | Purpose |
|-------|---------|
| `git-analyzer.md` | Analyzes git repo state for debugging |
| `bash-reviewer.md` | Reviews bash scripts for safety and portability |

---

## 13. HOOKS CONFIGURATION

Hooks are configured in `.claude/settings.json`. Current rules:

```json
{
  "permissions": {
    "allow": ["Bash(bash:*)", "Bash(git:*)", "Bash(chmod:*)", "Bash(mkdir:*)"],
    "deny":  ["Bash(git push --force*)", "Bash(git reset --hard*)", "Bash(rm -rf*)"]
  }
}
```

**PostToolUse suggestion**: After every `Edit` to `lib/*.sh`, auto-run `bash -n` on the file to catch syntax errors immediately.

---

## 14. PERMISSIONS & SAFETY

### Allowed automatically
- `bash` commands for running tests and syntax checks
- `git` read commands (log, status, diff, branch, show)
- `chmod` for making scripts executable

### Always requires confirmation
- `git push --force` or `--force-with-lease`
- `git reset --hard`
- `git branch -D` (force delete)
- Any command that modifies `.bashrc` / `.zshrc` / `.profile`

### Never do
- `rm -rf` on anything outside `/tmp/`
- Modify the user's global git config without explicit instruction
- Push to remote without the user asking

---

## 15. SLASH COMMANDS

| Command | Description |
|---------|-------------|
| `/new-subcommand <name>` | Scaffold a new subcommand with tests |
| `/add-test <subcommand>` | Add missing tests for a subcommand |
| `/release <version>` | Run release checklist and tag a version |
| `/security-audit` | Run full security scan on all scripts + agent analysis |

---

## 16. AGENTS

| Agent | Purpose |
|-------|---------|
| `git-analyzer` | Analyzes a git repo's state to help debug g-tool issues |
| `bash-reviewer` | Reviews bash scripts for safety, portability, and correctness |
| `security-auditor` | Comprehensive security audit — injection, path traversal, credential leaks |
| `injection-scanner` | Specialized injection scan — follows data flow from input to git commands |
| `secrets-detector` | Credential exposure audit — output leaks, missing detection patterns |

---

## 17. SECURITY HARDENING — AUDIT FINDINGS & FIXES

> Full audit was run on all lib/*.sh scripts. All critical and high findings have been fixed.

### Vulnerability Classes Addressed

| Class | Status | Where Fixed |
|-------|--------|-------------|
| Branch name injection (`$(cmd)`, backtick, `;`, `\|`, `&`) | **Fixed** | `lib/branch.sh` sanitization whitelist |
| Flag injection (branch names starting with `-`) | **Fixed** | `lib/branch.sh` strips leading dashes |
| `.lock` suffix collision | **Fixed** | `lib/branch.sh` strips `.lock` suffix |
| Missing `--` separator before git refs | **Fixed** | All `lib/*.sh` — `checkout`, `branch -d/D/m`, `push`, `restore`, `sync` |
| `sed` delimiter injection in stash messages | **Fixed** | `lib/stash.sh` uses bash parameter expansion |
| Search `--grep` flag injection | **Fixed** | `lib/search.sh` validates leading `--` |
| Accidental secret commit (API keys, tokens, private keys) | **Fixed** | `lib/commit.sh` `_check_staged_secrets()` |
| `eval` usage | **Verified absent** | `grep -r 'eval '` returns nothing |
| Force push without `--force-with-lease` | **Verified** | All push paths use `--force-with-lease` |
| `--onto` argument injection in `g sync` | **Fixed** | `lib/sync.sh` sanitizes via same whitelist as `branch.sh` |
| Stash ref injection via direct argument | **Fixed** | `lib/stash.sh` validates `stash@{N}` format before all pop/drop/show |
| Direct push to protected branches without warning | **Fixed** | `lib/push.sh` `_check_protected_branch()` |
| Inconsistent `--` before branch+base in checkout | **Fixed** | `lib/branch.sh:117` now uses `checkout -b -- "$safe_name" "$base"` |
| Temp file world-readable in uninstall.sh | **Fixed** | `uninstall.sh` uses `mktemp` + `chmod 600` immediately after |
| Missing secret patterns (GitLab, JWT, npm, DB URIs) | **Fixed** | `lib/commit.sh` expanded `SECRET_CONTENT_PATTERNS` and `SECRET_FILE_PATTERNS` |

### Security Rules — Always Follow

```
1. NEVER remove the -- separator before user-supplied git refs/branch names
2. NEVER change branch name sanitization to be more permissive
3. NEVER add eval — if dynamic dispatch is needed, use a case statement
4. NEVER skip _check_staged_secrets() in commit.sh
5. NEVER use git push --force — only --force-with-lease
6. ALWAYS run tests/test_security.sh after any change to lib/*.sh
```

### Branch Name Sanitization (lib/branch.sh)
```bash
# Whitelist: only alphanumeric + . - / _
safe_name=$(echo "$name" | sed 's/[[:space:]]/-/g' | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-zA-Z0-9._/\-]//g')
safe_name="${safe_name#-}"     # strip leading -
safe_name="${safe_name#-}"     # strip second - if --
safe_name="${safe_name%.lock}" # strip .lock suffix
```

### Secret Detection (lib/commit.sh)
Patterns that trigger a pre-commit warning:
- **Files**: `.env`, `.pem`, `.key`, `*_rsa`, `*_dsa`, `credentials*`, `secrets.*`, `.p12`, `.pfx`, `.netrc`, `.aws/credentials`, `.docker/config.json`, `.kube/config`, `.npmrc`, `.env.local`, `.vault-pass`, `terraform.tfvars`
- **Content**: AWS keys (`AKIA...`), GitHub tokens (`ghp_...`), GitLab tokens (`glo_/gla_...`), npm tokens (`npm_...`), PyPI tokens, private key headers (RSA/DSA/EC/OPENSSH), passwords in code, database URIs with credentials (`postgres://user:pass@`), JWT tokens (`eyJ...`)

### Running Security Checks
```bash
# Full security regression test suite
bash tests/test_security.sh

# Automated scan (slash command)
# In Claude: /security-audit

# Use agents for deep analysis
# @security-auditor   — full severity report
# @injection-scanner  — injection-focused scan
# @secrets-detector   — credential exposure gaps
```

---

## 18. CI / GITHUB ACTIONS LEARNINGS

> Recorded from the first CI run (2026-03-28). Each entry is a real failure we hit and fixed.

### git checkout -b and the -- separator

**Problem:** `git checkout -b -- "$branch"` was added as an injection guard. In git 2.23+ this is
parsed as: create a branch literally named `--`, using `$branch` as the start-point. All branch
creation silently failed; git printed a fatal error but the function continued.

**Rule:** Do NOT use `--` between `-b` and the branch name. Instead reject flag-injection at input
time with `case "$name" in -*) error ...; return 1 ;; esac` before sanitization.

```bash
# WRONG (git 2.23+): treats -- as the new branch name
git checkout -b -- "$safe_name"

# CORRECT: name already sanitized, -- not needed
git checkout -b "$safe_name"
```

Similarly, `git checkout -- "$target"` restores a *file* named `$target`, it does not switch
branches. Use `git checkout "$target"` for branch switching.

---

### confirm() must be testable via pipes

**Problem:** `confirm()` read unconditionally from `/dev/tty`. Tests using `echo "y" | func`
passed `y` to stdin, but confirm ignored stdin and got EOF from `/dev/tty` — always returning N.

**Rule:** Always fall back to stdin when not a TTY:

```bash
if [ -t 0 ]; then
  read -r answer </dev/tty
else
  read -r answer   # test pipes / CI
fi
```

---

### test helpers must use subshells

**Problem:** `assert_fails` ran the tested command directly with `if ! "$@"`. When `die()` was
called inside the tested function, `exit 1` killed the ENTIRE test script mid-run. All subsequent
assertions were skipped; `print_summary` never ran; the runner reported a cryptic non-zero exit.

**Rule:** Always wrap in `( )`:

```bash
if ! ( "$@" ) &>/dev/null; then   # subshell contains die()/exit
```

---

### run_tests.sh set -e vs failing test suites

**Problem:** `run_tests.sh` uses `set -euo pipefail`. When the first test suite (`test_branch`)
returned non-zero, `output=$(bash test_branch.sh 2>&1)` triggered `set -e` and killed the runner
immediately — all other suites were skipped and total counts were wrong.

**Rule:** Guard the capture with `set +e` / `set -e`:

```bash
set +e
output=$(bash "$test_file" 2>&1)
exit_code=$?
set -e
```

---

### ShellCheck in CI needs targeted exclusions

| Code | Reason to exclude | Where |
|------|-------------------|-------|
| SC1090/SC1091 | Dynamic `source "$(dirname ...)/core.sh"` paths | `bin/g`, `lib/*.sh`, `tests/*.sh` |
| SC2034 | Colors / vars defined in `core.sh` appear unused without source-following | `lib/*.sh`, `bin/g` |
| SC2164 | `cd` without `\|\| exit` — fine in test scripts | `tests/*.sh` |

---

### Portability regex false positives

**Problem:** The bash 4+ feature check grepped for `${var,}` and matched a COMMENT in
`commit.sh:169` that said `# NOTE: ${var,} is bash 4+ only`. The CI job failed on its own
documentation.

**Rule:** Filter comment lines from portability grep output:

```bash
grep -rEn 'pattern' lib/ bin/g 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'
```

---

### grep in pipeline with no matches exits 1 — `set -e` aborts silently (found 2026-04-01)

**Problem:** `git reflog ... | grep -E "checkout|branch" | head -20` — if the reflog has no checkout/branch entries (e.g. a brand-new repo), `grep` exits 1, the pipeline fails, and the script aborts with no user-visible error. Found in `_recover_branch()`.

**Rule:** Any `grep` that may legitimately find no matches must be wrapped with `|| true` when inside a pipeline under `set -euo pipefail`. Because of shell pipeline operator precedence, use braces:

```bash
# WRONG — silent abort when grep finds nothing
git reflog ... | grep -E "checkout|branch" | head -20 | while ...

# CORRECT — grep failure is handled, pipeline continues
{ git reflog ... | grep -E "checkout|branch" || true; } | head -20 | while ...
```

---

### `_print_stash_entries`: use `< <(...)` not pipe for `while` loop (found 2026-04-01)

When `while IFS= read -r line; do ... done` uses a pipe (`cmd | while`), the `while` body runs in a subshell. All other stash `while` loops use process substitution `< <(...)` — use that everywhere for consistency.

---

### Bash nested-brace expansion in `${param:-default}` (found 2026-04-01)

**Problem:** `"${ref:-stash@{0}}"` — bash does NOT treat `{0}` as a nested group in the default
word. The first `}` closes the `{0}`, and the SECOND `}` closes the outer `${...}` expansion. This
leaves the outer `}` as a literal character appended to the result. When `$ref` is already set to
`stash@{0}`, the output becomes `stash@{0}}` — causing the `^stash@\{[0-9]+\}$` regex to always fail.

**Rule:** Never put `{N}` literals inside `${...:-...}` default expressions. Use a conditional instead:

```bash
# WRONG — stray } appended when param is already set
local ref="${1:-stash@{0}}"

# CORRECT — avoids nested brace in default
local ref="${1:-}"
[ -z "$ref" ] && ref='stash@{0}'
```

---

### `git tag -a` flag order with `--` separator (found 2026-04-01)

**Problem:** `git tag -a -- "$version" -m "$message"` places `-m` after `--`, so git treats `-m`
as a positional argument (the tag name), and `"$message"` as an extra positional arg → `fatal: too many arguments`.

**Rule:** All flags must come before `--`:

```bash
# WRONG
git tag -a -- "$version" -m "$message"

# CORRECT
git tag -a -m "$message" -- "$version"
```

---

### Color variables in `core.sh` must use ANSI-C quoting (found 2026-04-01)

**Problem:** `RED='\033[0;31m'` (single-quoted) stores LITERAL chars `\033[0;31m`, not the ESC byte.
`echo -e` converts them at print time, but `cat <<EOF` heredocs do NOT — `show_help()` and all
`usage_*` functions use cat heredocs, so `${BOLD}`, `${CYAN}` etc. print as raw `\033[1m` on Linux.

**Rule:** Use `$'\033[...]'` (ANSI-C quoting) to embed the actual ESC byte (0x1B) at assignment time:

```bash
# WRONG — stores literal backslash chars, only echo -e handles them
BOLD='\033[1m'

# CORRECT — stores actual ESC byte, works in echo -e AND cat heredocs
BOLD=$'\033[1m'
```

---

## 19. BUG FIXING PROTOCOL (was 18)

```
1. Reproduce: identify the exact command + git state that triggers the bug
2. Read: read the relevant lib/*.sh in full before touching it
3. Isolate: find the exact line causing the issue
4. Fix: make the minimal change to fix it
5. Test: add a regression test in tests/test_<subcommand>.sh
6. Verify: bash tests/run_tests.sh — all must pass
7. Commit: "fix: <what was broken and how it was fixed>"
```

**Root cause over workaround**: If a git command behaves differently in bash 3.2 vs 5+, fix it properly with a version guard — don't just wrap it in `|| true`.

---

## 20. LONG-RUNNING TASK HANDLING

For tasks that take time (e.g. running against large repos):
- Use `run_in_background` for the task itself
- Provide progress feedback: `info "Analyzing ${count} commits..."` every N iterations
- All functions that may be slow should support `Ctrl+C` cleanly (no lingering temp files)
- Clean up temp files with a `trap 'rm -f "$TMP_FILE"' EXIT` pattern

---

## 21. TERMINAL & ENVIRONMENT

### PATH
```bash
# After install.sh, bin/ is in PATH:
export PATH="/path/to/git_tool/bin:$PATH"
```

### Environment Variables
```bash
G_DRY_RUN=1    # Preview all commands without executing
VERBOSE=1      # Verbose test output
G_NO_COLOR=1   # Disable color output (auto-disabled when not a TTY)
```

### Detecting bash version
```bash
BASH_MAJOR="${BASH_VERSINFO[0]}"
if [ "$BASH_MAJOR" -ge 4 ]; then
  # bash 4+ features available
fi
```

---

## 22. DO NOTs — Anti-Patterns

- **Never** use `eval` — command injection risk
- **Never** `cd` without checking it succeeded
- **Never** use `ls` output for iteration — use `find` or globs
- **Never** assume `main` is the default branch — use `git symbolic-ref refs/remotes/origin/HEAD`
- **Never** parse `git status` text output for scripting — use `git status --porcelain`
- **Never** create files in the user's working directory — only `/tmp/`
- **Never** modify git config without a backup and user confirmation
- **Never** use `git reset --hard` without showing the user what will be lost

---

## 23. WORKFLOW COVERAGE AUDIT

> Last reviewed: 2026-03-28. Re-run when adding subcommands.

### Developer Workflow Coverage Matrix

| Scenario | Covered By | Status |
|----------|-----------|--------|
| **SETUP** | | |
| Initialize a new repository | `g init` | ✓ |
| Set git identity (name/email) | `g init` step 1 | ✓ |
| Pick default branch | `g init` step 2 | ✓ |
| Create .gitignore from template | `g init` step 3 | ✓ |
| **DAILY** | | |
| Make and commit changes | `g commit` | ✓ |
| Push branch | `g push` | ✓ |
| Pull / sync with main | `g sync` | ✓ |
| See what changed | `g status`, `g diff` | ✓ |
| View history | `g log` | ✓ |
| **BRANCHING** | | |
| Create feature branch | `g branch <name>` | ✓ |
| Switch branches (fuzzy) | `g branch` | ✓ |
| Delete merged branches | `g clean` | ✓ |
| Compare branch vs main | `g diff main` | ✓ |
| **COMMITS** | | |
| Conventional commit format | `g commit` | ✓ |
| Amend last commit | `g commit --amend` | ✓ |
| Squash WIP commits | `g squash` | ✓ |
| **UNDO & RECOVERY** | | |
| Undo unpushed commit | `g undo commit` | ✓ |
| Undo a pushed commit | `g revert` | ✓ |
| Recover deleted branch | `g reflog --recover` | ✓ |
| Recover lost commits | `g reflog --recover` | ✓ |
| Discard file changes | `g undo file <path>` | ✓ |
| **CONFLICTS** | | |
| See conflicted files | `g conflict` | ✓ |
| Edit conflicted file | `g conflict edit` | ✓ |
| Mark file resolved | `g conflict resolve` | ✓ |
| Abort merge/rebase | `g conflict abort` | ✓ |
| **CODE REVIEW** | | |
| Create PR | `g pr create` | ✓ (requires gh) |
| Open PR in browser | `g pr open` | ✓ |
| View PR status/CI | `g pr status` | ✓ |
| Checkout someone's PR | `g pr checkout` | ✓ (requires gh) |
| Amend commits for review | `g fixup` | ✓ |
| Squash fixups before merge | `g fixup --autosquash` | ✓ |
| **RESEARCH** | | |
| Search commit messages | `g search` | ✓ |
| Search code changes | `g search --code` | ✓ |
| Who wrote this line? | `g blame` | ✓ |
| View staged diff | `g diff --staged` | ✓ |
| **RELEASES** | | |
| Create release tag | `g tag v1.2.0` | ✓ |
| List tags | `g tag` | ✓ |
| Push tag | `g tag --push` | ✓ |
| **HOUSEKEEPING** | | |
| Manage stashes | `g stash` | ✓ |
| Add to .gitignore | `g ignore` | ✓ |
| Save work in progress | `g stash save` | ✓ |
| Check setup | `g --doctor` | ✓ |

### Known Gaps (Not Yet Implemented)

| Gap | Impact | Notes |
|-----|--------|-------|
| Branch protection config (`G_PROTECTED_BRANCHES` env var to customize list) | LOW | Currently hardcoded pattern `main\|master\|develop\|...` in push.sh |
| `g bisect` — find which commit broke something | MEDIUM | `git bisect` works via pass-through |
| `g cherry` — cherry-pick commits across branches | MEDIUM | `git cherry-pick` works via pass-through |
| `g worktree` — manage parallel worktrees | LOW | `git worktree` works via pass-through |
| `g submodule` — submodule helpers | LOW | Niche use case; `git submodule` works via pass-through |
| Interactive rebase (`g rebase -i`) wrapper | MEDIUM | `git rebase -i` works via pass-through |
| Changelog generation from conventional commits | LOW | Would pair well with `g tag` |

### Pass-through Coverage
Any git command not recognized by `g` is passed directly to git. This means all git operations work — the tool enhances the most common ones.

```bash
g diff HEAD~3          # git diff HEAD~3
g cherry-pick abc123   # git cherry-pick abc123
g bisect start         # git bisect start
g rebase -i HEAD~5     # git rebase -i HEAD~5
g worktree list        # git worktree list
```

---

## 24. PROJECT-SPECIFIC RULES

- The tool's primary UX principle: **sensible defaults, explicit escapes** — every command works with zero arguments
- If `fzf` is available, use it for interactive selection; otherwise fall back to numbered list
- All subcommands must work in a repo with no commits (just `git init`)
- The `g` binary must be relocatable — no hardcoded absolute paths inside it
- Output must be readable without color (pipe-safe) — color only when stdout is a TTY
- Keep install.sh idempotent — running it twice must not break things
