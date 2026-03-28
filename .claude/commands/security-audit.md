---
description: Run a full security audit of all easy-git bash scripts
---

# Security Audit

Run a comprehensive security audit of all bash scripts in the easy-git tool.

## Step 1: Run the automated scan

```bash
# Check for missing -- separators before branch/ref names
echo "=== Missing -- separators ==="
grep -n 'git checkout\|git branch -d\|git branch -D\|git push.*\$branch\|git push.*\$name' lib/*.sh bin/g \
  | grep -v -- '-- ' | grep -v '#'

# Check for unquoted variables in command positions
echo "=== Potentially unquoted variables ==="
grep -nE 'git [a-z]+ \$[a-zA-Z]' lib/*.sh bin/g | grep -v '"' | grep -v '#'

# Check for eval usage
echo "=== eval usage (CRITICAL) ==="
grep -n 'eval ' lib/*.sh bin/g || echo "None found ✓"

# Check for branch name sanitization
echo "=== Branch sanitization function ==="
grep -A 15 'Sanitize branch name' lib/branch.sh

# Check for secret detection in commit
echo "=== Secret detection in commit ==="
grep -n 'SECRET\|credentials\|AKIA\|ghp_\|PRIVATE KEY' lib/commit.sh

# Check temp file security
echo "=== Temp file usage ==="
grep -n 'mktemp\|/tmp/' lib/*.sh bin/g tests/*.sh

# Check for hardcoded credentials
echo "=== Hardcoded credential patterns ==="
grep -nE '(password|token|secret|key)\s*=\s*["\x27][^"\x27]{6,}' lib/*.sh bin/g || echo "None found ✓"
```

## Step 2: Manual review checklist

Run this checklist against each lib/*.sh file:

- [ ] All user-supplied strings are quoted when passed to commands
- [ ] `--` separator used before all branch/ref/file args from user input
- [ ] Branch names validated against whitelist (alphanumeric + `.-/_`)
- [ ] Leading `-` stripped from branch names (prevents flag injection)
- [ ] No `eval` anywhere in the codebase
- [ ] Destructive commands require explicit `confirm()` before execution
- [ ] `git add -A` only after confirmation
- [ ] Force push uses `--force-with-lease` only
- [ ] `git restore` uses `-- "$file"` not bare `"$file"`
- [ ] `sed` commands do not use user input as the delimiter character

## Step 3: Use the security agents

Invoke the specialized agents for deeper analysis:
- `@security-auditor` — comprehensive severity-rated report
- `@injection-scanner` — focused injection vulnerability scan
- `@secrets-detector` — credential exposure and detection gaps

## Step 4: Run security regression tests

```bash
bash tests/test_security.sh
```

## Step 5: After fixing

For every fix, add a regression test to `tests/test_security.sh`:
```bash
assert_fails "branch name injection blocked" create_or_switch_branch '$(id)'
assert_fails "flag injection blocked"        create_or_switch_branch '--force'
```
