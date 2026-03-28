# easy-git (`g`) — Git made simple

> One short command. Every git workflow you need. Zero memorization required.

If you've ever typed `git add -A && git commit -m "stuff"` for the hundredth time, or forgotten the flags for `git push` on a new branch, or accidentally nuked changes with the wrong `git reset` — this tool is for you.

**easy-git** wraps the most common git operations into a single `g` command with smart defaults, clear output, and safety checks built in.

```
g s          → see what changed
g c          → commit (guided, step by step)
g p          → push (auto-sets upstream, offers to create a PR)
g b          → create or switch branches
g sy         → sync your branch with main
g l          → pretty log
g undo       → safely undo your last mistake
```

---

## What problem does this solve?

Raw git is powerful but has a steep learning curve. Common friction points:

| The frustration | What easy-git does |
|---|---|
| `git push` fails: *"no upstream branch"* | `g push` sets upstream automatically |
| Switching branches loses uncommitted work | `g branch` auto-stashes and restores |
| "How do I undo my last commit without losing work?" | `g undo` shows what it will do before doing it |
| Stale merged branches piling up | `g clean` finds and removes them with one command |
| Forgetting `git log --oneline --graph --decorate ...` | `g l` — that's it |
| Accidentally committing a `.env` file | `g commit` warns you before it happens |
| "What branch had that bug fix?" | `g search "bug description"` searches history |

---

## Requirements

You need these installed before setup:

- **git** (version 2.0 or newer) — [git-scm.com](https://git-scm.com)
- **bash** (version 3.2 or newer — already installed on macOS and Linux)

That's it. Everything else is optional.

### Check if you're ready

```bash
git --version   # should print: git version 2.x.x
bash --version  # should print: GNU bash, version 3.x or newer
```

---

## Installation

**Step 1 — Download the project**

```bash
git clone https://github.com/yourname/easy-git.git
cd easy-git
```

Or download and unzip it manually if you don't have git yet — ironic, but it works.

**Step 2 — Run the installer**

```bash
bash install.sh
```

This adds the `bin/` folder to your PATH in your shell config (`.bashrc`, `.zshrc`, or `.profile`). It does not modify anything else.

**Step 3 — Reload your terminal**

```bash
source ~/.bashrc      # if you use bash
# OR
source ~/.zshrc       # if you use zsh
```

Or just open a new terminal window.

**Step 4 — Verify it works**

```bash
g --version     # prints: g (easy-git) v1.0.0
g --help        # shows all commands
g --doctor      # checks your setup
```

---

## Optional extras (make it even better)

These are not required, but improve the experience:

| Tool | What it adds | Install |
|------|-------------|---------|
| **fzf** | Fuzzy search for branch switching and stash selection | `brew install fzf` / `apt install fzf` |
| **gh** | Create and manage GitHub pull requests from the terminal | [cli.github.com](https://cli.github.com) |
| **delta** | Nicer colored diffs | `brew install git-delta` |

Without fzf, `g branch` and `g stash` show a numbered list instead. Everything still works.

---

## Your first time using it

Navigate into any git repository and try these in order:

```bash
cd your-project

g s                 # see the current status of your repo
g l                 # see recent commit history
g b                 # list branches, pick one to switch
g c                 # make a commit (guided)
g p                 # push to remote
```

---

## Command reference

### `g status` (or `g s`)

Shows what's changed — staged, unstaged, untracked — with hints on what to do next.

```bash
g s
g s --short         # compact one-line-per-file format
```

**Example output:**
```
 Branch: feature/auth-fix
         ↑ 2 ahead  origin/feature/auth-fix — run g push when ready

Staged for commit:
  +  new file   src/auth.js
  ~  modified   src/login.js

Changes not staged:
  ~  modified   README.md

  To commit staged:   g commit
  To stage changes:   git add <file>  OR  git add -A
```

---

### `g commit` (or `g c`)

Interactive commit builder. Guides you through writing a good commit message.

```bash
g c                  # interactive — picks type, scope, subject
g c "fix: typo"      # quick commit with your own message
g c -a               # stage all tracked changes, then commit
g c --amend          # edit the last commit message
```

It will warn you if you're about to commit a file that looks like it contains secrets (`.env` files, `.aws/credentials`, `.kube/config`, private keys, AWS/GitHub/GitLab/npm tokens, database URIs, JWTs, etc.).

**Example session:**
```
Select commit type:
   1) feat:     A new feature
   2) fix:      A bug fix
   3) docs:     Documentation changes only
   ...

? Type [1-10]: 2

? Scope (optional, e.g. auth, api, ui):  auth

? Subject (short description):  handle null user on login

  fix(auth): handle null user on login

? Use this message? [y/N] y

✓ Committed [a3f9c12] on feature/auth-fix
  fix(auth): handle null user on login
→ Run 'g push' to push your changes.
```

---

### `g push` (or `g p`)

Pushes your branch. Sets the upstream automatically if it's a new branch. Offers to create a pull request when done (requires `gh`). Warns before pushing directly to protected branches (`main`, `master`, `develop`, etc.).

```bash
g p                  # push current branch
g p --force          # force push (uses --force-with-lease for safety)
g p --no-pr          # push without the PR creation prompt
```

---

### `g branch` (or `g b`)

Create branches, switch between them, or clean them up.

```bash
g b                           # interactive picker — choose a branch to switch to
g b feature/my-new-thing      # create a new branch and switch to it
g b -l                        # list all local branches
g b -d old-branch             # delete a merged branch
g b -D old-branch             # force-delete (even if not merged)
g b -r old-name new-name      # rename a branch
```

If you have uncommitted changes, `g branch` will ask whether to stash them and restore them after switching. You won't lose anything.

---

### `g sync` (or `g sy`)

Brings your current branch up to date with `main` (or `master`). This is what you run before opening a pull request, or after someone else merges changes.

```bash
g sy                 # rebase current branch onto main
g sy --merge         # use merge instead of rebase
g sy --onto develop  # sync with a different base branch
```

**What it does, step by step:**
1. Stashes your uncommitted changes (if any)
2. Fetches the latest from remote
3. Fast-forwards `main` to the latest
4. Rebases your branch on top of it
5. Restores your stashed changes

If there are conflicts, it stops and tells you exactly what to do.

---

### `g log` (or `g l`)

A readable, colored commit history — no long flags needed.

```bash
g l                        # default: last 20 commits with graph
g l -s                     # compact one-line format
g l -f                     # full details with file stats
g l -b                     # only commits on your branch (not in main)
g l -n 50                  # show last 50 commits
g l --author Alice         # only commits by Alice
g l --since "1 week ago"
g l --grep "auth"          # commits mentioning "auth"
g l --file src/auth.js     # full history of one file (follows renames)
```

---

### `g diff` (or `g d`)

Shows what changed. Without flags it shows unstaged changes; use `--staged` to see what's about to be committed.

```bash
g d                  # unstaged changes
g d --staged         # what's staged (about to be committed)
g d main             # compare current branch vs main
g d HEAD~2           # compare against 2 commits ago
```

Uses `delta` for nicer output if installed.

---

### `g undo` (or `g u`)

Safely undoes your last action. Always shows what it's about to do before doing it.

```bash
g undo               # guided menu — choose what to undo
g undo commit        # undo last commit, keep changes in working tree
g undo commit --soft # undo last commit, keep changes staged
g undo commit --hard # undo last commit and DISCARD all changes (careful!)
g undo push          # undo the last push (force-pushes with lease)
g undo file src/app.js  # discard changes to one specific file
```

**The guided menu looks like this:**
```
What do you want to undo?

  1) Last commit (keep changes staged)
  2) Last commit (keep changes unstaged)
  3) Last commit (DISCARD changes — irreversible)
  4) All unstaged changes to tracked files
  5) Specific file changes

? Choose [1-5]:
```

> **Tip:** When in doubt, choose option 1 or 2. You can always recommit.

---

### `g revert` (or `g rv`)

Safely undoes a commit that has already been pushed. Creates a new "revert" commit — never rewrites history, so it's safe on shared branches.

```bash
g rv                 # interactive: pick a commit to revert
g rv abc1234         # revert a specific commit by hash
```

> **Tip:** Use `g revert` for pushed commits. Use `g undo commit` for unpushed commits.

---

### `g squash` (or `g sq`)

Squashes multiple WIP commits into one clean commit before opening a PR.

```bash
g squash             # interactive: pick how many commits to squash
g squash --all       # squash all commits on this branch (vs main)
```

Warns you before rewriting history. Only use on commits not yet shared with others.

---

### `g fixup` (or `g fx`)

The code-review workflow: reviewer asks for a change → you fix it → attach the fix to the original commit → clean up history before merging.

```bash
g fixup              # stage your fix first, then pick the target commit
g fixup abc1234      # attach staged changes as a fixup to a specific commit
g fixup --autosquash # create fixup AND immediately squash it in
g fixup --squash     # like fixup but lets you edit the commit message
```

**Typical code review workflow:**
```bash
# Reviewer asks you to fix something in commit abc123
# Make the change, then:
g fixup abc123          # creates "fixup! original message" commit
g fixup --autosquash    # squash it in cleanly
g push --force          # update the PR
```

---

### `g conflict` (or `g cf`)

Guides you through resolving merge or rebase conflicts — works for all three states: merge, rebase, cherry-pick.

```bash
g conflict           # show conflicted files
g conflict edit      # open a conflicted file in your editor
g conflict resolve   # mark a file as resolved (git add)
g conflict abort     # abort the merge/rebase entirely
```

---

### `g tag` (or `g t`)

Create, list, delete, and push release tags.

```bash
g tag                       # list all tags
g tag v1.2.0                # create an annotated tag (recommended)
g tag v1.2.0 --push         # create and immediately push to remote
g tag v1.2.0 -m "Hotfix"    # tag with a custom message
g tag -d v1.1.0             # delete a tag (asks about remote too)
```

---

### `g stash`

Saves your current changes without committing, so you can come back to them later. Named stashes help you remember what's in each one.

```bash
g stash                       # save with auto-name (branch + timestamp)
g stash save "WIP: auth fix"  # save with a custom name
g stash pop                   # restore the most recent stash
g stash list                  # see all saved stashes
g stash drop                  # delete a stash you no longer need
g stash show                  # preview what's in a stash
```

---

### `g clean` (or `g cl`)

Removes branches that are no longer needed — branches fully merged into main, and branches whose remote counterpart has been deleted.

```bash
g clean --dry-run    # preview what would be deleted (no action)
g clean              # delete stale branches (asks for confirmation first)
g clean --gone       # only remove branches whose remote was deleted
```

Always preview with `--dry-run` first if you're unsure.

---

### `g blame` (or `g bl`)

Shows who wrote each line of a file and when.

```bash
g blame src/auth.js           # annotated view of the whole file
g blame src/auth.js -L 10,25  # only lines 10–25
```

---

### `g reflog` (or `g rl`)

Shows every action git has recorded — a safety net for recovering work that seems lost.

```bash
g reflog              # show full reflog
g reflog --recover    # guided wizard: restore a commit, branch, or lost work
```

> **Tip:** If you accidentally deleted a branch or did a hard reset, `g reflog --recover` can get it back.

---

### `g ignore` (or `g gi`)

Adds entries to your `.gitignore` without having to open the file manually.

```bash
g ignore .env                 # add .env to .gitignore
g ignore "*.log"              # add a pattern
g ignore --list               # see current .gitignore contents
g ignore --remove .env        # remove an entry
```

If a file is already tracked by git, it will offer to untrack it for you.

---

### `g search` (or `g sr`)

Searches through git history.

```bash
g search "login bug"              # search commit messages
g search --code "parseUser"       # find commits that changed code containing "parseUser"
g search --files "config"         # find files named *config* in history
g search "fix" --author Alice     # commits by Alice containing "fix"
g search "deploy" --since "2 weeks ago"
```

---

### `g pr`

Opens or creates pull requests. Requires the `gh` CLI.

```bash
g pr                 # auto: show existing PR, or offer to create one
g pr create          # create a PR for current branch (interactive)
g pr open            # open current branch's PR in browser
g pr list            # list all open PRs in the repo
g pr status          # show CI status of current branch's PR
g pr checkout        # checkout a PR branch interactively (or by number)
g pr checkout 42     # checkout PR #42 directly
```

---

### `g --doctor`

Checks that everything is set up correctly.

```bash
g --doctor
```

Output:
```
── g doctor — dependency check ────

✓  git — git version 2.43.0
✓  bash — GNU bash, version 5.2.21

○  fzf — not installed (optional) — brew install fzf / apt install fzf
○  gh  — not installed (optional) — https://cli.github.com
○  delta — not installed (optional) — brew install git-delta

✓  Git identity: Your Name <you@example.com>

g version: 1.0.0
```

---

## Everyday workflows

### Starting a new feature

```bash
g b feature/PROJ-42-add-login   # create branch
# ... write code ...
g s                              # check what changed
g c                              # commit
g p                              # push and create PR
```

### Updating your branch before a PR

```bash
g sy                             # sync with main
g p                              # push the rebased branch
```

### Fixing a mistake

```bash
g undo                           # guided menu
```

### Cleaning up after a merge

```bash
g b main                         # switch to main
g sy                             # pull latest
g clean                          # delete merged branches
```

### Handling code review feedback

```bash
# Reviewer asks you to fix something in commit abc123
# Make the change, then:
g fixup abc123       # attach fix to that commit
g fixup --autosquash # squash it in cleanly
g push --force       # update the PR
```

### Releasing a version

```bash
g sy                           # sync with main first
g tag v1.2.0 --push            # tag and push to remote
```

### Finding where a bug was introduced

```bash
g search --code "functionName"   # find commits that touched it
g l --grep "fix"                 # find fix commits
g l --file src/auth.js           # history of one specific file
```

### Recovering lost work

```bash
g reflog --recover   # guided wizard to recover deleted branches or commits
```

---

## Tips for beginners

**You can always use real git commands too.** `g` doesn't replace git — it adds shortcuts. Any command `g` doesn't recognize gets passed straight to git:

```bash
g diff              # same as: git diff
g rebase -i HEAD~3  # same as: git rebase -i HEAD~3
g cherry-pick abc123
```

**Dry-run mode** — add `G_DRY_RUN=1` before any command to see what it would do without doing it:

```bash
G_DRY_RUN=1 g sync    # shows the commands without running them
G_DRY_RUN=1 g clean   # same
```

**Every command has help:**

```bash
g commit --help
g branch --help
g sync --help
```

---

## Uninstalling

```bash
bash uninstall.sh
```

Or manually remove the line added to your `.bashrc` / `.zshrc`:

```bash
# Remove this line from your shell config:
export PATH="/path/to/easy-git/bin:$PATH"  # easy-git
```

---

## Troubleshooting

**`g: command not found`**
> Run `source ~/.bashrc` (or `.zshrc`) after installing, or open a new terminal.

**`g` runs the wrong command (system `g`)**
> Check `which g` — if it points somewhere unexpected, the install PATH may need to be placed earlier. Edit your shell config and move the `easy-git` export line higher up.

**`g branch` doesn't use fuzzy search**
> Install `fzf`: `brew install fzf` or `apt install fzf`. Without it, you get a numbered list instead.

**`g pr` says "gh not found"**
> Install the GitHub CLI: [cli.github.com](https://cli.github.com), then run `gh auth login`.

**Something went wrong and I want to check the repo state**
> Run `git status` and `git log --oneline -5` — these always work regardless of this tool.

---

## License

MIT — use it, modify it, share it.
