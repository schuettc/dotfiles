# Dotfiles Update Nudge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface a quiet "you're N commits behind — run dotup" nudge when `proj` starts, backed by a background-refreshed state file, so the machine never drifts silently.

**Architecture:** One new script `bin/dotfiles-update-check.sh` with three subcommands — `status` (instant read of a cached state file, prints one dim line if behind), `refresh` (age-gated `git fetch` + rewrite of the state file; never touches the working tree), `clear` (record up-to-date; called by `update.sh` after a successful pull). `proj` prints `status` and disowns `refresh` in the background.

**Tech Stack:** bash (3.2-safe, macOS `stat -f`), zsh test harness in `tests/`, git file-path remotes for test fixtures (no network).

**Spec:** `docs/superpowers/specs/2026-08-08-dotfiles-update-nudge-design.md`

## Global Constraints

- bash 3.2-safe in `bin/` scripts (no associative arrays, no `${var,,}`); `set -u`; macOS-only is fine (`stat -f %m`).
- Detection is strictly read-only against the repo: `fetch` only — never `pull`, never modify checked-out files.
- Quiet-indicator doctrine: the nudge is ONE dim line (`\033[2m…\033[0m`), no emoji, exact copy: `dotfiles: N behind · dotup`.
- Every failure path (no network, no repo, corrupt state) exits 0 silently — the nudge must never break or slow `proj`.
- All tests run offline: git fixtures use local directories as remotes.
- No documentation changes (minimal-docs doctrine — the nudge line itself names `dotup`).
- Execution happens in a git worktree branched off `main`. The spec and this plan exist only as untracked files in the primary clone at `/Users/courtschuett/dotfiles`; Task 1 copies them into the worktree and commits them.

---

### Task 1: `status` subcommand + test scaffold

**Files:**
- Create: `bin/dotfiles-update-check.sh` (status subcommand only; refresh/clear are later tasks)
- Create: `tests/dotfiles-update-check.test.zsh`
- Copy in + commit: `docs/superpowers/specs/2026-08-08-dotfiles-update-nudge-design.md`, `docs/superpowers/plans/2026-08-08-dotfiles-update-nudge.md`

**Interfaces:**
- Produces: `bin/dotfiles-update-check.sh [status]` — reads state file at `${DOTFILES_UPDATE_STATE:-$HOME/.cache/dotfiles-update-state}`; if it contains a line `behind=N` with N > 0, prints `\033[2mdotfiles: N behind · dotup\033[0m\n`; otherwise prints nothing. Always exits 0.
- Produces (for tests + later tasks): env overrides `DOTFILES_UPDATE_STATE` (state file path), `DOTFILES_UPDATE_REPO` (repo path, default `$HOME/dotfiles`), `DOTFILES_UPDATE_MAX_AGE` (seconds, default 14400).
- Produces: state file format — single line `behind=N`, file mtime = time of last check.

- [ ] **Step 1: Bring the spec and plan into the branch**

```bash
mkdir -p docs/superpowers/specs docs/superpowers/plans
cp /Users/courtschuett/dotfiles/docs/superpowers/specs/2026-08-08-dotfiles-update-nudge-design.md docs/superpowers/specs/
cp /Users/courtschuett/dotfiles/docs/superpowers/plans/2026-08-08-dotfiles-update-nudge.md docs/superpowers/plans/
git add docs/superpowers/specs/2026-08-08-dotfiles-update-nudge-design.md docs/superpowers/plans/2026-08-08-dotfiles-update-nudge.md
git commit -m "docs: spec + plan for dotfiles update nudge"
```

(If the worktree IS the primary clone path, the `cp` commands are no-ops that fail with "same file" — that's fine, just `git add` and commit.)

- [ ] **Step 2: Write the failing tests for `status`**

Create `tests/dotfiles-update-check.test.zsh`:

```zsh
#!/usr/bin/env zsh
# Tests for bin/dotfiles-update-check.sh (status / refresh / clear).
#
# Run directly:  zsh tests/dotfiles-update-check.test.zsh
#
# No network: refresh tests use a local directory as the git remote.

set -u

REPO="${0:A:h:h}"
SCRIPT="$REPO/bin/dotfiles-update-check.sh"

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

FAKE=$(mktemp -d)
trap 'rm -rf "$FAKE"' EXIT

export DOTFILES_UPDATE_STATE="$FAKE/state"
export DOTFILES_UPDATE_REPO="$FAKE/clone"

DIM_3=$'\033[2mdotfiles: 3 behind · dotup\033[0m'

# ── status ───────────────────────────────────────────────────────────────
echo "status:"

out=$("$SCRIPT" status)
ok "missing state file → silent" "" "$out"

printf 'behind=3\n' > "$FAKE/state"
out=$("$SCRIPT" status)
ok "behind=3 → dim nudge line" "$DIM_3" "$out"

out=$("$SCRIPT")
ok "status is the default subcommand" "$DIM_3" "$out"

printf 'behind=0\n' > "$FAKE/state"
out=$("$SCRIPT" status)
ok "behind=0 → silent" "" "$out"

printf 'behind=banana\n' > "$FAKE/state"
out=$("$SCRIPT" status)
ok "corrupt state → silent" "" "$out"

printf 'garbage\n' > "$FAKE/state"
out=$("$SCRIPT" status)
ok "unparseable state → silent" "" "$out"

# ── summary ──────────────────────────────────────────────────────────────
echo ""
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `zsh tests/dotfiles-update-check.test.zsh`
Expected: FAIL (or error) on every case — `bin/dotfiles-update-check.sh` does not exist yet.

- [ ] **Step 4: Write the script with the `status` subcommand**

Create `bin/dotfiles-update-check.sh`:

```bash
#!/bin/bash
# Update nudge for the dotfiles repo. Detection only — fetches, never pulls,
# never touches the working tree. `proj` prints `status` (instant file read)
# and fires `refresh` in the background; `update.sh` calls `clear` after a
# successful pull so the nudge dies immediately.
#
# Usage:
#   dotfiles-update-check.sh [status]   # dim one-liner if behind, else nothing
#   dotfiles-update-check.sh refresh    # age-gated fetch + rewrite state
#   dotfiles-update-check.sh clear      # record up-to-date
#
# State file (~/.cache/dotfiles-update-state): one line `behind=N`;
# mtime = last check. Env overrides (used by tests):
#   DOTFILES_UPDATE_STATE  DOTFILES_UPDATE_REPO  DOTFILES_UPDATE_MAX_AGE

set -u

STATE="${DOTFILES_UPDATE_STATE:-$HOME/.cache/dotfiles-update-state}"
REPO="${DOTFILES_UPDATE_REPO:-$HOME/dotfiles}"
MAX_AGE="${DOTFILES_UPDATE_MAX_AGE:-14400}"   # 4 hours

write_state() {
  mkdir -p "$(dirname "$STATE")" 2>/dev/null || return 0
  printf 'behind=%s\n' "$1" > "$STATE" 2>/dev/null
}

case "${1:-status}" in
  status)
    [[ -r "$STATE" ]] || exit 0
    behind=$(sed -n 's/^behind=\([0-9][0-9]*\)$/\1/p' "$STATE" | head -1)
    [[ -n "$behind" && "$behind" -gt 0 ]] || exit 0
    printf '\033[2mdotfiles: %s behind · dotup\033[0m\n' "$behind"
    ;;
  refresh)
    :   # Task 2
    ;;
  clear)
    :   # Task 3
    ;;
esac
exit 0
```

Then: `chmod +x bin/dotfiles-update-check.sh`

- [ ] **Step 5: Run tests to verify they pass**

Run: `zsh tests/dotfiles-update-check.test.zsh`
Expected: `6 passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add bin/dotfiles-update-check.sh tests/dotfiles-update-check.test.zsh
git commit -m "feat(update-nudge): status subcommand reading cached state"
```

---

### Task 2: `refresh` subcommand

**Files:**
- Modify: `bin/dotfiles-update-check.sh` (fill in the `refresh)` case)
- Modify: `tests/dotfiles-update-check.test.zsh` (append refresh section before the summary)

**Interfaces:**
- Consumes: state file format, env overrides, and `write_state` from Task 1.
- Produces: `refresh` — exits 0 silently unless ALL of: `$REPO` is a git work tree, state file is missing or older than `$MAX_AGE` seconds, `git fetch origin` succeeds, and `origin/main` resolves; then writes `behind=$(git rev-list --count HEAD..origin/main)`. On fetch failure the previous state file is left untouched.

- [ ] **Step 1: Write the failing tests**

In `tests/dotfiles-update-check.test.zsh`, insert before the `── summary` section:

```zsh
# ── refresh ──────────────────────────────────────────────────────────────
echo "refresh:"

# Fixture: local "origin" repo + a clone of it. Committing more in origin
# afterwards puts the clone behind — fetch is file-path local, no network.
G="git -c user.name=t -c user.email=t@t -c commit.gpgsign=false"
git init -q -b main "$FAKE/origin"
eval "$G -C '$FAKE/origin' commit -q --allow-empty -m c1"
git clone -q "$FAKE/origin" "$FAKE/clone"
eval "$G -C '$FAKE/origin' commit -q --allow-empty -m c2"
eval "$G -C '$FAKE/origin' commit -q --allow-empty -m c3"

rm -f "$FAKE/state"
"$SCRIPT" refresh
out=$(cat "$FAKE/state" 2>/dev/null)
ok "no state → fetches, records behind=2" "behind=2" "$out"

eval "$G -C '$FAKE/origin' commit -q --allow-empty -m c4"
"$SCRIPT" refresh
out=$(cat "$FAKE/state" 2>/dev/null)
ok "fresh state → age-gated, no refetch" "behind=2" "$out"

touch -t 202001010000 "$FAKE/state"
"$SCRIPT" refresh
out=$(cat "$FAKE/state" 2>/dev/null)
ok "stale state → refetches, behind=3" "behind=3" "$out"

git -C "$FAKE/clone" remote set-url origin "$FAKE/nonexistent"
touch -t 202001010000 "$FAKE/state"
"$SCRIPT" refresh
out=$(cat "$FAKE/state" 2>/dev/null)
ok "fetch failure → prior state kept" "behind=3" "$out"
git -C "$FAKE/clone" remote set-url origin "$FAKE/origin"

mkdir -p "$FAKE/notarepo"
rm -f "$FAKE/state"
DOTFILES_UPDATE_REPO="$FAKE/notarepo" "$SCRIPT" refresh
ok "not a git repo → silent, no state written" "no-state" "$([[ -e $FAKE/state ]] && echo state || echo no-state)"
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `zsh tests/dotfiles-update-check.test.zsh`
Expected: the 6 status tests pass; the refresh tests FAIL (refresh is a no-op stub, so no state file is written — first refresh test expects `behind=2`, gets empty).

- [ ] **Step 3: Implement `refresh`**

Replace the `refresh)` case body in `bin/dotfiles-update-check.sh`:

```bash
  refresh)
    git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
    now=$(date +%s)
    mtime=$(stat -f %m "$STATE" 2>/dev/null || echo 0)
    (( now - mtime < MAX_AGE )) && exit 0
    git -C "$REPO" fetch --quiet origin 2>/dev/null || exit 0
    git -C "$REPO" rev-parse --verify --quiet origin/main >/dev/null 2>&1 || exit 0
    behind=$(git -C "$REPO" rev-list --count HEAD..origin/main 2>/dev/null) || exit 0
    write_state "$behind"
    ;;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh tests/dotfiles-update-check.test.zsh`
Expected: `11 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add bin/dotfiles-update-check.sh tests/dotfiles-update-check.test.zsh
git commit -m "feat(update-nudge): age-gated refresh via read-only fetch"
```

---

### Task 3: `clear` subcommand + `update.sh` integration

**Files:**
- Modify: `bin/dotfiles-update-check.sh` (fill in the `clear)` case)
- Modify: `update.sh` (call `clear` after the successful pull, before `./install.sh`)
- Modify: `tests/dotfiles-update-check.test.zsh` (append clear section before the summary)

**Interfaces:**
- Consumes: `write_state` from Task 1.
- Produces: `clear` — writes `behind=0` with a fresh mtime (so the age gate also resets). Correct because `update.sh` only reaches it after `git pull --rebase` succeeded, at which point `HEAD..origin/main` is empty by definition.

- [ ] **Step 1: Write the failing test**

In `tests/dotfiles-update-check.test.zsh`, insert before the `── summary` section:

```zsh
# ── clear ────────────────────────────────────────────────────────────────
echo "clear:"

printf 'behind=7\n' > "$FAKE/state"
"$SCRIPT" clear
out=$(cat "$FAKE/state" 2>/dev/null)
ok "clear → behind=0" "behind=0" "$out"

out=$("$SCRIPT" status)
ok "status after clear → silent" "" "$out"
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `zsh tests/dotfiles-update-check.test.zsh`
Expected: 11 pass; `clear → behind=0` FAILs (stub does nothing, state still `behind=7`).

- [ ] **Step 3: Implement `clear`**

Replace the `clear)` case body in `bin/dotfiles-update-check.sh`:

```bash
  clear)
    write_state 0
    ;;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh tests/dotfiles-update-check.test.zsh`
Expected: `13 passed, 0 failed`

- [ ] **Step 5: Wire into `update.sh`**

In `update.sh`, after the pull block (the `if ! git pull --rebase --autostash; then … fi`) and before the `echo "→ Applying (brew packages + symlinks)…"` line, insert:

```bash
# Pull succeeded → we're current; kill the update nudge immediately rather
# than letting it linger until the next fetch window.
"$DOTFILES_DIR/bin/dotfiles-update-check.sh" clear
```

- [ ] **Step 6: Verify update.sh still parses and the call works**

Run: `bash -n update.sh && DOTFILES_UPDATE_STATE=/tmp/nudge-check-$$ bash -c '"$PWD/bin/dotfiles-update-check.sh" clear && cat /tmp/nudge-check-$$ && rm /tmp/nudge-check-$$'`
Expected: no syntax error; prints `behind=0`.

- [ ] **Step 7: Commit**

```bash
git add bin/dotfiles-update-check.sh tests/dotfiles-update-check.test.zsh update.sh
git commit -m "feat(update-nudge): clear subcommand, wired into dotup"
```

---

### Task 4: `proj` hook + manual verification

**Files:**
- Modify: `config/zsh/04-aliases.zsh` — inside `proj()`, after the `--edit`/`--add`/`--remove` early-return blocks and immediately before the `local auto_agent=""` line (currently line ~390)

**Interfaces:**
- Consumes: `bin/dotfiles-update-check.sh` `status` and `refresh` subcommands (Tasks 1–2).
- Produces: nothing new — this is the surfacing point. The hook deliberately skips the `--edit`/`--add`/`--remove` paths (config editing, no picker to sit above).

- [ ] **Step 1: Add the hook**

In `config/zsh/04-aliases.zsh`, between the `--remove` block's closing `fi` and `local auto_agent=""`, insert:

```zsh
  # Update nudge: instant read of the last check's state (one dim line above
  # the picker, or nothing), then refresh in the background for next time —
  # the picker never waits on the network.
  "$HOME/dotfiles/bin/dotfiles-update-check.sh" status
  "$HOME/dotfiles/bin/dotfiles-update-check.sh" refresh >/dev/null 2>&1 &!
```

(`&!` = zsh background + disown, matching how the repo avoids job-control noise. The `$HOME/dotfiles` path matches the existing `__proj_right_column` helper on line ~182.)

- [ ] **Step 2: Syntax-check the zsh file**

Run: `zsh -n config/zsh/04-aliases.zsh`
Expected: no output, exit 0.

- [ ] **Step 3: Run the full test suite**

Run: `for t in tests/*.test.zsh; do echo "== $t"; zsh "$t" || echo "SUITE FAILED: $t"; done`
Expected: all suites pass, including the pre-existing `proj-picker` and `proj-roots` suites (the hook must not break them — if either fails, the hook placement is wrong).

- [ ] **Step 4: Manual end-to-end check**

```bash
# Simulate being behind, then eyeball the nudge exactly as proj would print it:
printf 'behind=2\n' > "$HOME/.cache/dotfiles-update-state"
"$PWD/bin/dotfiles-update-check.sh" status        # → dim "dotfiles: 2 behind · dotup"
"$PWD/bin/dotfiles-update-check.sh" clear
"$PWD/bin/dotfiles-update-check.sh" status        # → nothing
# Real refresh against the actual repo (network ok here):
rm -f "$HOME/.cache/dotfiles-update-state"
"$PWD/bin/dotfiles-update-check.sh" refresh
cat "$HOME/.cache/dotfiles-update-state"          # → behind=N for the real repo
```

Expected: outputs as annotated; refresh completes in ~1s and writes a plausible count.

- [ ] **Step 5: Commit**

```bash
git add config/zsh/04-aliases.zsh
git commit -m "feat(proj): surface dotfiles update nudge above the picker"
```
