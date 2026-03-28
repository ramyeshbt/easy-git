---
description: Release checklist — run tests, bump version, tag
argument-hint: <version> (e.g. 1.1.0)
---

# Release: v$ARGUMENTS

Run the full release checklist for easy-git v$ARGUMENTS.

## Checklist

1. **Run full test suite**
```bash
bash tests/run_tests.sh
```
All tests must pass before proceeding.

2. **Syntax check all scripts**
```bash
bash -n bin/g
for f in lib/*.sh; do bash -n "$f" && echo "OK: $f"; done
```

3. **Check for hardcoded paths**
```bash
grep -n '"/home\|"/Users\|C:\\' lib/*.sh bin/g
```
Must return no matches.

4. **Bump version** in `bin/g`:
   - Find `G_VERSION="..."` and update to `$ARGUMENTS`

5. **Update CLAUDE.md** if needed — note any new subcommands or breaking changes.

6. **Commit the release**:
```bash
git add bin/g CLAUDE.md
git commit -m "chore: release v$ARGUMENTS"
```

7. **Tag the release**:
```bash
git tag -a "v$ARGUMENTS" -m "Release v$ARGUMENTS"
```

8. **Verify installation works**:
```bash
bash install.sh
g --version
g --doctor
g --help
```

9. **Push tags**:
```bash
git push && git push --tags
```

## Done!
