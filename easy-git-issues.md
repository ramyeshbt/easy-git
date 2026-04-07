# easy-git Bug Report & Findings Log

> Running history of all bugs found, fixed, and observations made during testing.
> Each entry records the symptom, root cause, fix applied, and the commit that resolved it.

---

## Session 1 — Manual sandbox testing (non-TTY environment)

> Found by running every `g` command in a non-interactive Linux sandbox (Ubuntu 24, no TTY).

---

### Bug 1 — `prompt_input()` crashes in non-TTY environments

**Affected file:** `lib/core.sh` — `prompt_input()` (line 164)

**Symptom:**
```
/home/claude/easy-git/bin/../lib/core.sh: line 164: /dev/tty: No such device or address
```
Triggered whenever `g init` (or any command using `prompt_input`) ran outside a real terminal — CI, VS Code integrated terminal, piped input, subprocess.

**Root cause:**
`prompt_input()` read unconditionally from `/dev/tty` with no TTY fallback, unlike `confirm()` which already had the correct `[ -t 0 ]` guard.

**Fix:**
```bash
if [ -t 0 ]; then
  read -r value </dev/tty
else
  read -r value
fi
```

**Fixed in:** `cbb3693`

---

### Bug 2 — `fuzzy_select()` numbered-list fallback crashes in non-TTY

**Affected file:** `lib/core.sh` — `fuzzy_select()` (line 146)

**Symptom:** Same `/dev/tty: No such device or address` crash when fzf was absent and the numbered-list fallback ran in a non-TTY environment.

**Root cause:** Same unconditional `read -r choice </dev/tty` with no guard.

**Fix:** Same `[ -t 0 ]` guard with stdin fallback.

**Fixed in:** `cbb3693`

---

### Bug 3 — `g undo commit` hangs indefinitely in non-TTY

**Affected file:** `lib/undo.sh` — `undo_commit()` (line 83)

**Symptom:** `g undo commit` typed at a shell prompt in a non-TTY sandbox blocked forever waiting for input that never arrived.

**Root cause:** `confirm()` falls back to `read` on stdin when not a TTY. With nothing piped in, `read` blocks forever.

**Fix:** Added `-y`/`--yes` flag + auto-detect:
```bash
local yes=0
[ ! -t 0 ] && yes=1   # auto-confirm in non-TTY

if [ "$yes" -eq 0 ]; then
  confirm "Undo this commit?" || return 1
fi
```

**Fixed in:** `cbb3693`

---

## Session 2 — bash-reviewer agent audit

> Triggered automatically after the Session 1 fixes. Agent reviewed `lib/core.sh` and `lib/undo.sh`.

---

### Bug 4 — `undo_last()` unconditional `/dev/tty` read (missed in Session 1)

**Affected file:** `lib/undo.sh` — `undo_last()` (line 35)

**Symptom:** `g undo` (no subcommand — interactive menu) would crash with `/dev/tty: No such device` in CI or piped environments.

**Root cause:** The Session 1 fix applied the TTY guard to `undo_commit()` but missed `undo_last()` which had the same bare `read -r choice </dev/tty`.

**Fix:** Same `[ -t 0 ]` guard.

**Fixed in:** `8f2ba96`

---

### Bug 5 — `undo_push()` `--force-with-lease` placed after `--`

**Affected file:** `lib/undo.sh` — `undo_push()` (line 133)

**Symptom:** `g undo push` would fail because git treated `--force-with-lease` as an invalid refspec argument.

**Root cause:**
```bash
# WRONG — --force-with-lease is after --, treated as refspec
git push "$remote" -- "$branch" --force-with-lease
```
Git's `--` signals end-of-options. Everything after it is positional.

**Fix:**
```bash
git push --force-with-lease "$remote" -- "$branch"
```

**Fixed in:** `8f2ba96`

---

### Bug 6 — `undo_file_interactive()` strips 3 chars from `git diff --name-only` output

**Affected file:** `lib/undo.sh` — `undo_file_interactive()` (line 163)

**Symptom:** File names shown in the interactive picker had their first 3 characters silently stripped. A file named `src/main.sh` appeared as `main.sh`; a file named `go.mod` appeared as `od`.

**Root cause:** The function used `git diff --name-only` (no prefix), but the code had `local file="${line:3}"` — a copy-paste from `git status --porcelain` parsing, which does have a 2-char status code + space prefix. The strip was completely wrong for `--name-only` output.

**Fix:** Removed the `:3` strip.
```bash
changed_files+=("$line")   # was: changed_files+=("${line:3}")
```

**Fixed in:** `8f2ba96`

---

## Session 3 — Beginner walkthrough testing

> Tested every command in a fresh `/tmp/beginner-test` repo simulating how a new user would interact with the tool — without reading the manual, using natural input patterns.

---

### Bug 7 — `g commit` crashes in non-TTY (type picker read)

**Affected file:** `lib/commit.sh` (line 159)

**Symptom:** `g commit` crashed immediately with `/dev/tty: No such device or address` when piped input was used.

**Root cause:** The numbered commit-type picker used `read -r choice </dev/tty` unconditionally — same pattern as the Session 1 bugs, but in a different file that was never audited.

**Fix:** `if [ -t 0 ]; then read -r choice </dev/tty; else read -r choice; fi`

**Fixed in:** `8da02d6`

---

### Bug 8 — `g commit` breaking-change description crashes in non-TTY

**Affected file:** `lib/commit.sh` (line 187)

**Symptom:** When the user answered "yes" to "Is this a breaking change?", the follow-up description prompt crashed with `/dev/tty: No such device or address`.

**Root cause:** `read -r breaking </dev/tty` — unconditional.

**Fix:** Same `[ -t 0 ]` guard.

**Fixed in:** `8da02d6`

---

### Bug 9 — `g commit` body while-loop crashes in non-TTY

**Affected file:** `lib/commit.sh` (line 201)

**Symptom:** The optional multi-line commit body prompt crashed in non-TTY.

**Root cause:** `while IFS= read -r line </dev/tty; do` — redirect inside the while condition, unconditional.

**Fix:** Wrapped in `if [ -t 0 ]; then ... TTY loop ... else ... stdin loop ... fi`

**Fixed in:** `8da02d6`

---

### Bug 10 — `g pr` description while-loop crashes in non-TTY

**Affected file:** `lib/pr.sh` (line 81)

**Symptom:** `g pr create` crashed at the PR description prompt in non-TTY environments.

**Root cause:** Identical pattern to Bug 9 — `while IFS= read -r line </dev/tty` with no TTY guard.

**Fix:** Same `if [ -t 0 ]` dual-loop pattern.

**Fixed in:** `8da02d6`

---

### Bug 11 — `g reflog --recover` crashes in non-TTY (two reads)

**Affected file:** `lib/reflog.sh` (lines 52, 87)

**Symptom:** `g reflog --recover` crashed at both the recovery mode picker and the reset mode picker.

**Root cause:** Two separate `read -r choice </dev/tty` calls with no TTY guard — in `reflog_recover()` and `_recover_to_point()`.

**Fix:** `if [ -t 0 ]; then read -r choice </dev/tty; else read -r choice; fi` at both sites.

**Fixed in:** `8da02d6`

---

### Bug 12 — `g blame` shows header but zero output (silent data loss)

**Affected file:** `lib/blame.sh` — `_format_blame()` (line 69)

**Symptom:** `g blame <file>` printed "Blame: filename" and then nothing — no lines, no error.

**Root cause:** The porcelain format content lines start with a literal tab character. The regex used to detect them was:
```bash
elif [[ "$line" =~ ^\t(.*)$ ]]; then
```
In bash `=~` (ERE), `\t` is **not** interpreted as a tab — it matches a literal backslash followed by `t`. No content line ever matched, so no output was ever printed.

**Fix:**
```bash
elif [[ "${line:0:1}" == $'\t' ]]; then
  content="${line:1}"
```
Uses bash substring comparison with an ANSI-C quoted tab literal — works in bash 3.2+.

**Fixed in:** `8da02d6`

---

## UX Observations (not bugs — future improvement candidates)

| Observation | Command | Notes |
|---|---|---|
| `g diff` says "No unstaged changes" on brand-new untracked files | `g diff` | Technically correct — untracked files aren't "modified". A hint like *"New files? Use `git add <file>` to start tracking."* would help beginners. |
| `g search --code` exits with code 1 on no results | `g search --code` | Surprising for scripts. Most search tools exit 0 on "found nothing" and 1 on error. Could confuse `if g search --code "token"; then ...` patterns. |
| `g squash` blocks on `main` with an error | `g squash` | Correct safety guard, but a beginner won't know they need a feature branch first. The error message is clear but could suggest `g branch feature/x` as the next step. |

---

## Running totals

| Session | Bugs found | Bugs fixed | Commits |
|---|---|---|---|
| Session 1 — Sandbox testing | 3 | 3 | `cbb3693` |
| Session 2 — bash-reviewer agent | 3 | 3 | `8f2ba96` |
| Session 3 — Beginner walkthrough | 6 | 6 | `8da02d6` |
| **Total** | **12** | **12** | — |

---

## Pattern: TTY detection gap

The most common bug class across all three sessions was **missing `[ -t 0 ]` guards on `read` calls**. The fix is always identical:

```bash
# WRONG — crashes when /dev/tty is unavailable
read -r value </dev/tty

# CORRECT — falls back to stdin in non-TTY environments
if [ -t 0 ]; then
  read -r value </dev/tty
else
  read -r value
fi
```

**CLAUDE.md rules added:** Rule 26 (TTY guard on every `read`) and Rule 27 (non-interactive subcommands need `--yes`/`-y` flag).

After all three sessions, a final scan confirmed **zero remaining unconditional `/dev/tty` reads** outside of existing `[ -t 0 ]` guards across all `lib/*.sh` files.
