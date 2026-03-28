---
description: Scaffold a new g subcommand with implementation and tests
argument-hint: <subcommand-name> "<short description>"
---

# New Subcommand: $ARGUMENTS

Create a complete new `g` subcommand called **`$ARGUMENTS`** for the easy-git tool.

## Steps

1. **Read existing patterns** — Read `lib/commit.sh` and `lib/branch.sh` to understand the conventions before writing anything.

2. **Create `lib/<name>.sh`** with:
   - `#!/usr/bin/env bash` shebang
   - `source "$(dirname "${BASH_SOURCE[0]}")/core.sh"`
   - `main_<name>()` function as the entry point
   - `--help / -h` flag handled first
   - `usage_<name>()` function with full help text
   - All output using `success()`, `warn()`, `error()`, `info()`, `hint()` from core.sh
   - `require_git_repo` or `require_git_repo_with_commits` guard at the top
   - Every destructive action guarded by `confirm()`

3. **Register in `bin/g`** — Add the subcommand and its alias to the `dispatch()` case statement.

4. **Create `tests/test_<name>.sh`** with:
   - At least 3 meaningful tests
   - Uses `setup_repo` / `teardown_repo` from `tests/helpers.sh`
   - Covers: happy path, edge cases, error cases

5. **Update CLAUDE.md §9** — Add the new subcommand to the Subcommand Reference table.

## Verification
```bash
bash -n lib/<name>.sh
bash tests/test_<name>.sh
bash tests/run_tests.sh
```
