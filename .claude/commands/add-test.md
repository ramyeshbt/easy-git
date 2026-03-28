---
description: Add missing tests for a g subcommand
argument-hint: <subcommand-name>
---

# Add Tests for: g $ARGUMENTS

Add comprehensive tests for the `g $ARGUMENTS` subcommand.

## Steps

1. **Read `lib/$ARGUMENTS.sh`** in full to understand all code paths.

2. **Read `tests/helpers.sh`** to understand available assert functions.

3. **Read existing test files** (e.g. `tests/test_branch.sh`) for style reference.

4. **Identify coverage gaps** — list every function and condition not yet tested.

5. **Write tests in `tests/test_$ARGUMENTS.sh`** covering:
   - Happy path (normal usage)
   - Edge cases: empty repo, detached HEAD, no remote, dirty working tree
   - Error cases: invalid flags, wrong arguments
   - Each destructive action is properly guarded

6. **Run the tests**:
```bash
bash tests/test_$ARGUMENTS.sh
```

## Guidelines
- Each test uses `setup_repo` and `teardown_repo`
- Use `echo "y" |` to simulate user confirming prompts
- Use `echo "n" |` to simulate user cancelling
- Test non-interactive paths where possible (use flags to bypass prompts)
