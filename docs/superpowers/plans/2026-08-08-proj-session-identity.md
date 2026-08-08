# proj Session-Identity Realignment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The tmux session name becomes the work's identity — proj creates `<project>/<work>` sessions instead of numbered slots and worktree checkouts, prefix T becomes the all-surfaces rename gesture, and the statusline renames the session (instead of labeling it) when the operator `/rename`s inside Claude.

**Architecture:** Spec: `docs/superpowers/specs/2026-08-08-proj-session-identity-design.md`. The neutral tmux↔muster meeting point moves from the `@claude_task`/`@claude_task_manual` option pair to the session name (`#S`). Division of labor everywhere: **dotfiles owns the tmux rename; muster's `become` owns the bus alias claim and `/rename` injection.** `@claude_task` survives as a display-only subtitle; `@claude_task_manual` is retired; `@claude_task_promoted` (stale-title guard) is kept. All worktree machinery in proj is deleted, not relocated.

**Tech Stack:** zsh (04-aliases.zsh, 06-tmux-autojoin.zsh), bash (bin/ scripts, statusline.sh), tmux ≥3.7, fzf/fd. Tests are standalone `tests/*.test.zsh` files run directly (`zsh tests/<name>.test.zsh`) against a real throwaway tmux server, using the repo's `ok()` PASS/FAIL convention.

## Global Constraints

- **dotfiles ⊥ muster:** every gesture must work with plain tmux (no muster on PATH). Muster-present paths probe `muster become --help` and degrade to tmux-only when the probe fails (a pre-`become`-CLI muster).
- **No send-keys** anywhere in this repo's naming scripts — typing into panes is muster's job.
- **Never demote:** no code path may rename a session from an auto topic. Renames come only from operator gestures (prefix T) or a transcript-proven user-set `/rename`.
- **Work-name charset:** `<work>` is `[A-Za-z0-9_-]+`; full session names (rename surface) are `[A-Za-z0-9_/-]+`. No `.`, `:`, whitespace (tmux target separators).
- **Collision refusal:** a rename never takes a name any live session on any tmux server holds (the name doubles as the bus-global alias).
- **Execute in a git worktree** (superpowers:using-git-worktrees) — the primary clone is a coordination point; this session (`dotfiles-2`) lives there.
- Muster-repo changes are coordinated via the bus (Task 6), never implemented from this repo.

---

### Task 1: prefix T becomes the rename gesture

**Files:**
- Create: `bin/tmux-session-rename.sh`
- Create: `tests/tmux-session-rename.test.zsh`
- Modify: `.tmux.conf` (the `bind T` line ~147 and its comment block ~126–146)
- Delete: `bin/tmux-muster-label.sh`, `tests/tmux-muster-label.test.zsh`

**Interfaces:**
- Consumes: `#{pane_id}` from the binding; `muster become <name>` CLI when present (probed via `muster become --help`).
- Produces: the shim's observable behavior — validates, refuses collisions, `tmux rename-session`, then optionally `muster become`. Task 2's statusline and Task 3's picker rely on `#S` being the identity this gesture maintains.

- [ ] **Step 1: Write the failing test**

`tests/tmux-session-rename.test.zsh`:

```zsh
#!/usr/bin/env zsh
# Tests for bin/tmux-session-rename.sh: prefix T renames the SESSION (the
# name is the identity — session-identity plan 2026-08-08). Must validate
# the charset, refuse names live sessions hold on ANY server, work with
# and without muster, and never send-keys.
set -u
REPO="${0:A:h:h}"

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}
command -v tmux >/dev/null || { echo "tmux required"; exit 1; }

WORK=$(mktemp -d)
# The shim scans ${TMUX_TMPDIR}/tmux-$UID/* for collisions — point that at
# a private dir so the test sees only its own servers.
export TMUX_TMPDIR="$WORK"
SOCKDIR="$WORK/tmux-$(id -u)"
trap 'tmux -S "$SOCKDIR/main" kill-server 2>/dev/null;
      tmux -S "$SOCKDIR/other" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT

mkdir -p "$SOCKDIR"
tmux -S "$SOCKDIR/main" new-session -d -s start-name -x 80 -y 24
PANE=$(tmux -S "$SOCKDIR/main" display-message -p -t start-name '#{pane_id}')
export TMUX="$SOCKDIR/main,999,0"

name() { tmux -S "$SOCKDIR/main" display-message -p '#{session_name}'; }

# ── muster ABSENT: plain-tmux rename ────────────────────────────────
print '── fallback (no muster) ──'
PATH_SAVE="$PATH"
# Keep tmux reachable while dropping muster (~/.local/bin): a bare
# /usr/bin:/bin would strip Homebrew's tmux and break the shim itself.
TMUXDIR="$(dirname "$(command -v tmux)")"
NOMUSTER_PATH="$TMUXDIR:/usr/bin:/bin"
if command -v muster >/dev/null 2>&1 \
   && [[ "$(dirname "$(command -v muster)")" == "$TMUXDIR" ]]; then
  echo "muster shares tmux's dir — NOMUSTER_PATH can't strip it"; exit 1
fi
export PATH="$NOMUSTER_PATH"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "dotfiles/nfl-4"
ok "renames the session"        "dotfiles/nfl-4" "$(name)"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "bad name"
ok "invalid charset refused"    "dotfiles/nfl-4" "$(name)"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "bad:name"
ok "colon refused"              "dotfiles/nfl-4" "$(name)"
"$REPO/bin/tmux-session-rename.sh" "$PANE" ""
ok "empty input is a no-op"     "dotfiles/nfl-4" "$(name)"

# ── collision with a live session on ANOTHER server ─────────────────
print '── cross-server collision ──'
tmux -S "$SOCKDIR/other" new-session -d -s taken-name -x 80 -y 24
"$REPO/bin/tmux-session-rename.sh" "$PANE" "taken-name"
ok "name held elsewhere refused" "dotfiles/nfl-4" "$(name)"
export PATH="$PATH_SAVE"

# ── muster PRESENT: become delegation AFTER the tmux rename ─────────
print '── delegation (fake muster with become) ──'
mkdir -p "$WORK/bin"
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
[ "$1" = "become" ] || exit 1
exit 0
EOF
chmod +x "$WORK/bin/muster"
export PATH="$WORK/bin:$NOMUSTER_PATH" MUSTER_ARGS_LOG="$WORK/args.log"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "dotfiles/nfl-5"
ok "tmux renamed first"       "dotfiles/nfl-5" "$(name)"
ok "delegates to become"      "become dotfiles/nfl-5" "$(tail -1 "$MUSTER_ARGS_LOG")"

# ── muster present but PRE-become (probe fails): tmux-only ──────────
print '── degradation (muster without become) ──'
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
exit 1
EOF
chmod +x "$WORK/bin/muster"
: > "$MUSTER_ARGS_LOG"
"$REPO/bin/tmux-session-rename.sh" "$PANE" "dotfiles/nfl-6"
ok "still renames tmux"          "dotfiles/nfl-6" "$(name)"
ok "only the probe hit muster"   "become --help" "$(cat "$MUSTER_ARGS_LOG")"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
```

- [ ] **Step 2: Run to verify it fails**

Run: `zsh tests/tmux-session-rename.test.zsh`
Expected: FAIL — `bin/tmux-session-rename.sh` does not exist yet.

- [ ] **Step 3: Write the shim**

`bin/tmux-session-rename.sh`:

```bash
#!/bin/bash
# prefix T handler: rename this SESSION — one gesture for every surface
# (session-identity plan 2026-08-08; spec in docs/superpowers/specs/).
#
# The tmux session name IS the identity: #S = the work = (with muster) the
# bus alias. The tmux half lives here: validate, refuse collisions, rename.
# With muster present, `muster become <name>` additionally claims the alias
# on the bus (mail follows via lineage) and types /rename into the
# registered Claude pane — muster owns injection; this script never
# send-keys. A muster whose CLI predates `become` fails the probe and the
# rename stays tmux-only (Claude's internal name catches up on the
# operator's next /rename).
#
# tmux run-shell children inherit $TMUX but NOT $TMUX_PANE — $1 is
# #{pane_id}, expanded by the binding at press time; $2 is the new name.
# Output goes through display-message: run-shell opens a full-screen view
# for ANY stdout, which reads as an error screen instead of feedback.
export TMUX_PANE="$1"
new="$2"

cur=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}')

if [[ -z "$new" || "$new" == "$cur" ]]; then
  tmux display-message "rename cancelled (still: $cur)"
  exit 0
fi

if [[ ! "$new" =~ ^[A-Za-z0-9_/-]+$ ]]; then
  tmux display-message "invalid name: $new (allowed: letters digits - _ /)"
  exit 0
fi

# Refuse names a LIVE session already holds — on any server, because the
# name doubles as the bus-global muster alias. Silent identity theft is the
# failure mode this exists to prevent.
sockdir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
for s in "$sockdir"/*; do
  [[ -S "$s" ]] || continue
  if tmux -S "$s" has-session -t "=$new" 2>/dev/null; then
    tmux display-message "name taken by a live session: $new"
    exit 0
  fi
done

tmux rename-session -t "$TMUX_PANE" "$new"

if command -v muster >/dev/null 2>&1 && muster become --help >/dev/null 2>&1; then
  if out=$(muster become "$new" 2>&1); then
    tmux display-message "renamed → $new · muster: ${out//$'\n'/ · }"
  else
    tmux display-message "renamed → $new · muster become FAILED: ${out//$'\n'/ · }"
  fi
else
  tmux display-message "renamed → $new (tmux only)"
fi
tmux refresh-client -S
```

`chmod +x bin/tmux-session-rename.sh`.

- [ ] **Step 4: Run to verify it passes**

Run: `zsh tests/tmux-session-rename.test.zsh`
Expected: `PASS=9 FAIL=0`, exit 0.

- [ ] **Step 5: Rebind prefix T and delete the old shim**

In `.tmux.conf`, replace the comment block + binding (currently lines ~126–147, from `# Task label for this session (prefix T)…` through the `bind T` line) with:

```tmux
# Rename this session (prefix T) — the ONE naming gesture. The session name
# IS the identity (#S = the work = the muster alias when muster is present).
# bin/tmux-session-rename.sh validates ([A-Za-z0-9_/-]), refuses names any
# live session holds, renames the tmux session, and — with muster — calls
# `muster become`, which claims the bus alias (mail follows via lineage) and
# types /rename into the registered Claude pane. Without muster (or with a
# pre-become muster) the rename is tmux-only. Empty input cancels.
# Routed through the shim because run-shell children get $TMUX but not
# $TMUX_PANE, and any stdout would open as a full-screen error view.
bind T command-prompt -I '#S' -p 'rename session:' 'run-shell -b "~/dotfiles/bin/tmux-session-rename.sh #{pane_id} \"%%\""'
```

Then: `git rm bin/tmux-muster-label.sh tests/tmux-muster-label.test.zsh`

- [ ] **Step 6: Commit**

```bash
git add bin/tmux-session-rename.sh tests/tmux-session-rename.test.zsh .tmux.conf
git commit -m "feat(tmux): prefix T renames the session — one gesture, all surfaces"
```

---

### Task 2: statusline renames instead of labeling

**Files:**
- Modify: `config/claude/statusline.sh` (header comment lines 14–15 and the whole name-sync block, lines 61–152)
- Rewrite: `tests/statusline-name-sync.test.zsh`

**Interfaces:**
- Consumes: statusline JSON stdin `.session_name` / `.transcript_path`; transcript `{"type":"custom-title"}` records; `muster become --no-inject <name>` when the `muster become --help` probe passes.
- Produces: `#S` aligned to a user-set Claude name; `@claude_task` = display-only subtitle (whatever Claude currently calls the conversation); `@claude_task_promoted` = last title acted on. Nothing writes `@claude_task_manual` anymore.

- [ ] **Step 1: Rewrite the test file**

Replace the whole of `tests/statusline-name-sync.test.zsh` with:

```zsh
#!/usr/bin/env zsh
# Tests for statusline.sh's name-sync block (session-identity plan
# 2026-08-08): a user-set name (transcript custom-title == session_name)
# RENAMES the tmux session; auto topics only write the @claude_task
# subtitle; a stale title (== the promoted marker) never reverts an
# operator rename; collisions with live sessions refuse the rename.
set -u
REPO="${0:A:h:h}"

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}
command -v tmux >/dev/null || { echo "tmux required"; exit 1; }
command -v jq   >/dev/null || { echo "jq required";   exit 1; }

WORK=$(mktemp -d)
export TMUX_TMPDIR="$WORK"          # scoped: the collision scan globs this
SOCKDIR="$WORK/tmux-$(id -u)"
trap 'tmux -S "$SOCKDIR/main" kill-server 2>/dev/null;
      tmux -S "$SOCKDIR/other" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT
mkdir -p "$SOCKDIR"
tmux -S "$SOCKDIR/main" new-session -d -s start-name -x 80 -y 24
PANE=$(tmux -S "$SOCKDIR/main" display-message -p -t start-name '#{pane_id}')
export TMUX="$SOCKDIR/main,999,0" TMUX_PANE="$PANE"

name()   { tmux -S "$SOCKDIR/main" display-message -p '#{session_name}'; }
sub()    { tmux -S "$SOCKDIR/main" show-option -qv -t "$PANE" @claude_task; }
marker() { tmux -S "$SOCKDIR/main" show-option -qv -t "$PANE" @claude_task_promoted; }

TRANSCRIPT="$WORK/t.jsonl"
statusline() {  # $1 = session_name, $2 = transcript path ("" for none)
  jq -n --arg n "$1" --arg tp "$2" \
    '{model:{display_name:"Fable"},context_window:{used_percentage:10},
      workspace:{current_dir:"/w"},session_name:$n,transcript_path:$tp}' \
    | bash "$REPO/config/claude/statusline.sh" >/dev/null 2>&1
}

PATH_SAVE="$PATH"
# Keep tmux and jq reachable while dropping muster (~/.local/bin): a bare
# /usr/bin:/bin would strip the Homebrew binaries the script under test uses.
NOMUSTER_PATH="$(dirname "$(command -v tmux)"):$(dirname "$(command -v jq)"):/usr/bin:/bin"
if PATH="$NOMUSTER_PATH" command -v muster >/dev/null 2>&1; then
  echo "muster still reachable on NOMUSTER_PATH — adjust the test"; exit 1
fi

# ── auto topic: subtitle only, session name untouched ───────────────
print '── auto topic → subtitle only ──'
printf '%s\n' '{"type":"user"}' > "$TRANSCRIPT"
export PATH="$NOMUSTER_PATH"
statusline "Debug tmux titles" "$TRANSCRIPT"
ok "session name untouched"  "start-name"        "$(name)"
ok "topic lands in subtitle" "Debug tmux titles" "$(sub)"

# ── user-set valid name, muster absent: tmux rename ─────────────────
print '── user-set name → rename (no muster) ──'
printf '%s\n' '{"type":"custom-title","customTitle":"dotfiles/nfl-4","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "dotfiles/nfl-4" "$TRANSCRIPT"
ok "session renamed"  "dotfiles/nfl-4" "$(name)"
ok "marker recorded"  "dotfiles/nfl-4" "$(marker)"

# ── stale title never reverts an operator rename ────────────────────
print '── stale title vs prefix T ──'
tmux -S "$SOCKDIR/main" rename-session -t "=dotfiles/nfl-4" "operator-name"
statusline "dotfiles/nfl-4" "$TRANSCRIPT"   # transcript still holds the OLD title
ok "operator rename survives" "operator-name" "$(name)"

# ── invalid charset: subtitle only, even when user-set ──────────────
print '── invalid charset never renames ──'
printf '%s\n' '{"type":"custom-title","customTitle":"has spaces","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "has spaces" "$TRANSCRIPT"
ok "no rename on bad charset" "operator-name" "$(name)"
ok "subtitle still updates"   "has spaces"    "$(sub)"

# ── collision: a live session elsewhere holds the name ──────────────
print '── collision refusal ──'
tmux -S "$SOCKDIR/other" new-session -d -s wanted -x 80 -y 24
printf '%s\n' '{"type":"custom-title","customTitle":"wanted","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "wanted" "$TRANSCRIPT"
ok "held name not stolen" "operator-name" "$(name)"

# ── muster present: become --no-inject after the rename ─────────────
print '── delegation (fake muster with become) ──'
mkdir -p "$WORK/bin"
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
[ "$1" = "become" ] || exit 1
exit 0
EOF
chmod +x "$WORK/bin/muster"
export PATH="$WORK/bin:$NOMUSTER_PATH" MUSTER_ARGS_LOG="$WORK/args.log"
printf '%s\n' '{"type":"custom-title","customTitle":"dotfiles/nfl-7","sessionId":"u1"}' > "$TRANSCRIPT"
statusline "dotfiles/nfl-7" "$TRANSCRIPT"
ok "renamed with muster present" "dotfiles/nfl-7" "$(name)"
ok "become --no-inject called"   "become --no-inject dotfiles/nfl-7" "$(tail -1 "$MUSTER_ARGS_LOG")"

# ── aligned fast path: no transcript read ───────────────────────────
print '── aligned fast path ──'
export PATH="$NOMUSTER_PATH"
statusline "dotfiles/nfl-7" "$WORK/does-not-exist.jsonl"   # would fail if read mattered
ok "aligned state stays put" "dotfiles/nfl-7" "$(name)"
ok "marker seeded"           "dotfiles/nfl-7" "$(marker)"

export PATH="$PATH_SAVE"
print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
```

- [ ] **Step 2: Run to verify it fails**

Run: `zsh tests/statusline-name-sync.test.zsh`
Expected: the auto-topic subtitle case may PASS (today's auto branch also writes the label); every rename case FAILs (today's code sets label options, never renames).

- [ ] **Step 3: Replace the name-sync block**

In `config/claude/statusline.sh`: change header responsibility 3 (lines 14–15) to `#   3. Keep the tmux session name aligned with a user-set Claude name` / `#      (/rename) and mirror Claude's current name/topic into the` / `#      @claude_task subtitle.` Then replace everything from the `# ─── Sync Claude session name → tmux task label` header comment (line 61) through its closing `fi` (line 152) with:

```bash
# ─── Sync Claude session name ↔ tmux session name ────────────────────
# The tmux session name IS the identity (session-identity plan 2026-08-08;
# spec docs/superpowers/specs/2026-08-08-proj-session-identity-design.md).
# Claude ships `session_name` in the statusline JSON — an explicit /rename
# AND the auto-generated topic land in the same field; a transcript
# {"type":"custom-title"} record whose customTitle equals session_name
# proves the name is USER-SET. Rules:
#   • user-set + valid charset ([A-Za-z0-9_/-]) + differs from #S and from
#     the promoted marker + no live session anywhere holds it → RENAME the
#     tmux session, then `muster become --no-inject` when available (the
#     name already came from /rename — injecting it back would loop).
#   • everything else → @claude_task subtitle only: whatever Claude calls
#     the conversation, for the title's middle segment (the title template
#     dedupes it against #S). NOTHING here renames from an auto topic.
# @claude_task_promoted records the last title this script acted on: a
# STALE transcript title (prefix-T's /rename keystrokes eaten by a busy
# turn — seen live 2026-08-06) must not revert an operator rename on the
# next tick. Aligned sessions seed the marker on the cheap path (no
# transcript read). Accepted limitation (unchanged from the label era):
# /renaming BACK to the exact marker value after a prefix-T divergence is
# ignored — rename through a different name first.
SESSION_NAME=$(echo "$input" | jq -r '.session_name // ""')
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // ""')
if [[ -n "$SESSION_NAME" && -n "${TMUX_PANE:-}" ]]; then
  tmux_name=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)
  promoted=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task_promoted 2>/dev/null)
  if [[ "$SESSION_NAME" == "$tmux_name" ]]; then
    # fast path: aligned — keep the marker seeded, read nothing else.
    if [[ "$promoted" != "$SESSION_NAME" ]]; then
      tmux set-option -t "$TMUX_PANE" @claude_task_promoted "$SESSION_NAME" 2>/dev/null
    fi
  else
    # Subtitle first: display-only and safe for every kind of name.
    current_sub=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task 2>/dev/null)
    if [[ "$current_sub" != "$SESSION_NAME" ]]; then
      tmux set-option -t "$TMUX_PANE" @claude_task "$SESSION_NAME" 2>/dev/null
      tmux refresh-client -S 2>/dev/null
    fi
    # Rename only for a FRESH, machine-shaped, user-set name.
    if [[ "$SESSION_NAME" != "$promoted" && "$SESSION_NAME" =~ ^[A-Za-z0-9_/-]+$ ]]; then
      custom_title=""
      if [[ -n "$TRANSCRIPT_PATH" && -r "$TRANSCRIPT_PATH" ]]; then
        custom_title=$(grep '"custom-title"' "$TRANSCRIPT_PATH" 2>/dev/null \
          | tail -1 | jq -r '.customTitle // ""' 2>/dev/null)
      fi
      if [[ -n "$custom_title" && "$custom_title" == "$SESSION_NAME" ]]; then
        # Refuse names a live session holds — the name doubles as the
        # bus-global alias; identity theft must be explicit.
        taken=0
        sockdir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
        for s in "$sockdir"/*; do
          [[ -S "$s" ]] || continue
          tmux -S "$s" has-session -t "=$SESSION_NAME" 2>/dev/null && { taken=1; break; }
        done
        if (( ! taken )); then
          tmux rename-session -t "$TMUX_PANE" "$SESSION_NAME" 2>/dev/null
          if command -v muster >/dev/null 2>&1; then
            # A pre-become muster fails the probe; the rename above already
            # landed — tmux-only is the accepted degradation.
            muster become --help >/dev/null 2>&1 \
              && muster become --no-inject "$SESSION_NAME" >/dev/null 2>&1
          fi
          tmux set-option -t "$TMUX_PANE" @claude_task_promoted "$SESSION_NAME" 2>/dev/null
          tmux refresh-client -S 2>/dev/null
        fi
      fi
    fi
  fi
fi
```

- [ ] **Step 4: Run to verify it passes**

Run: `zsh tests/statusline-name-sync.test.zsh`
Expected: `PASS=12 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add config/claude/statusline.sh tests/statusline-name-sync.test.zsh
git commit -m "feat(statusline): user-set /rename renames the tmux session; auto topics are subtitle-only"
```

---

### Task 3: picker Screen 2 — sessions, not branches

**Files:**
- Modify: `config/zsh/04-aliases.zsh` — header comments (~137–179), delete `__proj_launch_numbered` / `__proj_copy_includes` / `__proj_ensure_worktree` / `__proj_worktree_list` / `__proj_prune_worktrees` (~300–425), refactor `__proj_launch` (~260), rewrite `proj()`'s Screen 2 (~530–582)
- Modify: `tests/proj-picker.test.zsh` (extend; keep existing Screen-1 cases)

**Interfaces:**
- Consumes: `__proj_load_roots` / `__proj_dir_for_name` / `__proj_servers` / `__proj_srv` / `__proj_goto` / `__proj_find_server` / `__proj_right_column` / `__tmux_new_session` — all unchanged from 03-proj-roots.zsh and earlier in 04-aliases.zsh.
- Produces (Task 4 depends on these exact names): `__proj_valid_work <name>` (0 iff `[A-Za-z0-9_-]+`); `__proj_read_work` (prompts on /dev/tty, prints the name); `__proj_session_list <project>` (Screen-2 rows); `__proj_screen2 <primary-dir> <project> [agent]`; `__proj_ensure_session <srv> <name> <dir> [agent]` (create + layout, no attach); `__proj_launch <srv> <name> <dir> [agent]` (= ensure + goto, signature unchanged); `proj [<flags>] [<project>]` (positional project jumps straight to Screen 2).

- [ ] **Step 1: Extend the test file**

Append to `tests/proj-picker.test.zsh` (before the final PASS/FAIL print; move that print to the end). Also update its preamble stubs: keep `tmux() { return 1; }` and `__proj_launch() { return 0; }`, delete the `__proj_worktree_list() { return 0; }` stub (the function will no longer exist):

```zsh
echo "── Screen 2: sessions, not branches ──"
print -- "$TMP/GitHub" > "$ROOTS"
# Re-stub launch to RECORD its arguments (still never runs tmux).
__proj_launch() { print -r -- "$1|$2|$3|${4:-}" > "$TMP/launch"; }
rm -f "$TMP/launch"
script_picker "$TMP/GitHub/repo-a" "$ESC"
proj >/dev/null 2>&1
ok "screen 2 shown"          "2" "$(shown)"
ok "home base row offered"   "1" "$(menu 2 | grep -cF -- '🏠 repo-a')"
ok "new-work row offered"    "1" "$(menu 2 | grep -cF -- '+ new work…')"
ok "no worktree rows"        "0" "$(menu 2 | grep -c -- '▸\|worktree\|branch')"
ok "screen 2 is 2 rows"      "2" "$(menu 2 | wc -l | tr -d ' ')"

echo "── + new work creates <project>/<work> in the primary clone ──"
__proj_read_work() { print -r -- "nfl-4"; }
script_picker "$TMP/GitHub/repo-a" "+ new work…"
proj >/dev/null 2>&1
ok "launch called with the work name" \
   "proj-repo-a|repo-a/nfl-4|$TMP/GitHub/repo-a|" "$(cat "$TMP/launch")"

echo "── invalid work names are refused ──"
__proj_read_work() { print -r -- "bad name"; }
rm -f "$TMP/launch"
script_picker "$TMP/GitHub/repo-a" "+ new work…"
proj >/dev/null 2>&1
ok "no launch on invalid name" "" "$(cat "$TMP/launch" 2>/dev/null)"

echo "── home base row opens the bare project session ──"
rm -f "$TMP/launch"
script_picker "$TMP/GitHub/repo-a" "🏠 repo-a — home base (primary clone)"
proj >/dev/null 2>&1
ok "home base launches bare name" \
   "proj-repo-a|repo-a|$TMP/GitHub/repo-a|" "$(cat "$TMP/launch")"

echo "── proj <project> jumps straight to Screen 2 ──"
rm -f "$TMP/launch"
script_picker "$ESC"
proj repo-a >/dev/null 2>&1
ok "screen 1 skipped"          "1" "$(shown)"
ok "screen 2 menu shown first" "1" "$(menu 1 | grep -cF -- '+ new work…')"

echo "── live sessions listed identity-first, legacy names included ──"
__proj_servers() { print -- fake; }
tmux() {
  case "$*" in
    *" ls -F"*) printf 'repo-a/nfl-3\ttopic x\nrepo-a-2\t\nrepo-b/other\t\n';;
    *) return 1;;
  esac
}
script_picker "$TMP/GitHub/repo-a" "$ESC"
proj >/dev/null 2>&1
ok "named session listed with topic" "1" "$(menu 2 | grep -cF -- '● repo-a/nfl-3  — topic x')"
ok "legacy numbered slot listed"     "1" "$(menu 2 | grep -cF -- '● repo-a-2')"
ok "other project's session hidden"  "0" "$(menu 2 | grep -cF -- 'repo-b/other')"
tmux() { return 1; }
__proj_servers() { return 0; }
```

- [ ] **Step 2: Run to verify it fails**

Run: `zsh tests/proj-picker.test.zsh`
Expected: the pre-existing Screen-1 cases PASS; every new case FAILs (Screen 2 still shows worktree rows; `__proj_read_work` / `proj <project>` don't exist).

- [ ] **Step 3: Rewrite the proj half of 04-aliases.zsh**

3a. Replace the two header comment blocks (lines ~137–164, `# ─── tmux + projects (worktree-aware)…` through `…See 03-proj-roots.zsh.`) with:

```zsh
# ─── tmux + projects (session-identity) ────────────────────────────────────
# Project session picker. The SESSION NAME is the identity: a session is
# born named for its work — `<project>/<work>` (home base: bare
# `<project>`) — and every surface aligns to that one name (tab titles,
# this picker, and, when muster is installed, the bus alias its
# SessionStart hook seeds from the session name). Two fzf steps:
#   1. pick a project (or jump straight to a live session)
#   2. pick a session, open the home base, or name new work
# Isolation is the AGENT'S job (its own worktrees), not the picker's —
# proj creates every session in the primary clone.
#
# Usage:
#   proj              # two-screen picker
#   proj <project>    # jump straight to Screen 2 for that project
#   proj --claude     # auto-launch Claude in the new session's left pane
#   proj --cursor     # auto-launch Cursor in the new session's left pane
#   proj --edit       # open ~/.config/proj/roots in $EDITOR
#   proj --add        # add a root, or a single directory as a project
#   proj --remove     # delete entries from the roots file (Tab = multi-select)
#
# Layout for every session: agent-or-shell on the left, scratch/yazi/shell
# column on the right. Renames go through prefix T (bin/tmux-session-
# rename.sh) so no surface is left behind. Project roots:
# ~/.config/proj/roots — see 03-proj-roots.zsh.
```

3b. Split `__proj_launch` (~line 260): rename the existing function to `__proj_ensure_session` and delete its final `__proj_goto "$srv" "$name"` line, then add below it:

```zsh
# Create-or-attach: ensure the session exists, then move this client to it.
__proj_launch() {
  __proj_ensure_session "$@"
  __proj_goto "$1" "$2"
}
```

(Keep `__proj_ensure_session`'s body — the has-session guard, agent send-keys, right column — byte-for-byte otherwise.)

3c. Delete these functions entirely (~lines 300–425): `__proj_launch_numbered`, `__proj_copy_includes`, `__proj_ensure_worktree`, `__proj_worktree_list`, `__proj_prune_worktrees`. In their place add:

```zsh
# A work name: one path segment of the session identity. Letters, digits,
# hyphen, underscore — no '.', ':' or whitespace (tmux target separators);
# '/' is reserved for the <project>/<work> join.
__proj_valid_work() { [[ "$1" =~ '^[A-Za-z0-9_-]+$' ]]; }

# Prompt for a work name on the tty (factored out so tests can stub it).
__proj_read_work() {
  local w
  printf "Work name (letters digits - _): " >/dev/tty
  IFS= read -r w </dev/tty || return 1
  print -r -- "$w"
}

# Build the Screen-2 list: live sessions of this project (● name — topic),
# the home base, and the new-work action. Legacy names (<project>-N,
# <project>/<branch>) keep showing while they're alive — migration is
# "rename as you touch them", never forced.
__proj_session_list() {
  local project="$1" lsrv name label
  for lsrv in $(__proj_servers); do
    tmux -L "$lsrv" ls -F $'#{session_name}\t#{@claude_task}' 2>/dev/null
  done | sort -u | while IFS=$'\t' read -r name label; do
    if [[ "$name" == "$project" || "$name" == "$project"/* || "$name" == "$project"-<-> ]]; then
      print -r -- "● ${name}${label:+  — $label}"
    fi
  done
  print -r -- "🏠 ${project} — home base (primary clone)"
  print -r -- "+ new work…"
}

# Screen 2: this project's sessions — jump to one, open the home base, or
# name new work. New sessions are created as <project>/<work> in the
# primary clone; isolation (worktrees) is the agent's job, not the picker's.
__proj_screen2() {
  local primary="$1" project="$2" auto_agent="${3:-}"
  local psrv; psrv=$(__proj_srv "$project")
  local pick
  pick=$(__proj_session_list "$project" \
           | fzf --prompt="$project › " --height=60% --reverse)
  [[ -z "$pick" ]] && return 0
  case "$pick" in
    "● "*)
      local name="${pick#● }" d srv
      name="${name%%  — *}"   # drop the topic suffix
      srv=$(__proj_find_server "$name") || { echo "session gone: $name" >&2; return 1; }
      d=$(tmux -L "$srv" display-message -p -t "=$name" '#{pane_current_path}' 2>/dev/null)
      [[ -n "$d" && -d "$d" ]] && cd "$d"
      __proj_goto "$srv" "$name"
      ;;
    "🏠 "*)
      __proj_launch "$psrv" "$project" "$primary" "$auto_agent"
      ;;
    "+ new work…")
      local w
      w=$(__proj_read_work) || return 0
      [[ -z "$w" ]] && return 0
      __proj_valid_work "$w" \
        || { echo "invalid work name: $w (allowed: letters digits - _)" >&2; return 1; }
      __proj_launch "$psrv" "$project/$w" "$primary" "$auto_agent"
      ;;
  esac
}
```

3d. In `proj()`: after the `--claude`/`--cursor` flag loop, capture `local direct_project="${1:-}"`. After the roots-loading block (the `if ! __proj_load_roots; then … fi`), insert:

```zsh
  # `proj <project>` — skip Screen 1 (auto-join and muscle memory both use it).
  if [[ -n "$direct_project" ]]; then
    local dpdir
    dpdir=$(__proj_dir_for_name "$direct_project") \
      || { echo "project not found: $direct_project" >&2; return 1; }
    __proj_screen2 "$dpdir" "${dpdir:t}" "$auto_agent"
    return
  fi
```

3e. Replace everything in `proj()` after the `[session] ` jump-handling block (i.e. from `local primary="$choice" project="${choice:t}"` through the end of the old Screen-2 `case` statement, ~lines 530–582) with:

```zsh
  __proj_screen2 "$choice" "${choice:t}" "$auto_agent"
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `zsh tests/proj-picker.test.zsh`
Expected: all cases PASS (old Screen-1 cases and the new Screen-2 cases), exit 0. Also run `zsh tests/proj-roots.test.zsh` — must still pass (03-proj-roots.zsh is untouched).

- [ ] **Step 5: Commit**

```bash
git add config/zsh/04-aliases.zsh tests/proj-picker.test.zsh
git commit -m "feat(proj): Screen 2 is sessions, not branches — named work, no worktree machinery"
```

---

### Task 4: pt and auto-join stop minting slots

**Files:**
- Modify: `config/zsh/04-aliases.zsh` — rewrite `pt()` (~lines 570–640 after Task 3's edits; find via `grep -n '^pt()'`)
- Modify: `config/zsh/06-tmux-autojoin.zsh` — replace the slot-minting tail (lines ~64–99)
- Create: `tests/pt-autojoin.test.zsh`

**Interfaces:**
- Consumes: `__proj_valid_work`, `__proj_ensure_session`, `__proj_launch`, `__proj_name_for_dir`, `__proj_dir_for_name`, `__proj_srv` (Task 3); `proj [<flags>] <project>` direct mode (Task 3).
- Produces: `pt [--claude|--cursor] [<project>] <work>`; `__proj_attach_exec <srv> <name>` (exec-attach endgame, stubbed by tests); auto-join that only ever calls `proj`.

- [ ] **Step 1: Write the failing test**

`tests/pt-autojoin.test.zsh`:

```zsh
#!/usr/bin/env zsh
# pt and the auto-join hook after the session-identity change: pt creates
# <project>/<work> (never a numbered slot); auto-join never mints sessions
# — it hands the project to proj's Screen 2.
REPO="${0:A:h:h}"
source "$REPO/config/zsh/03-proj-roots.zsh"
source "$REPO/config/zsh/04-aliases.zsh"
unalias -m '*'

typeset -g PASS=0 FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); printf '  ok   %s\n' "$1"
  else
    (( FAIL++ )); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/GitHub/repo-a"
export XDG_CONFIG_HOME="$TMP/xdg"
mkdir -p "$XDG_CONFIG_HOME/proj"
print -- "$TMP/GitHub" > "$XDG_CONFIG_HOME/proj/roots"

# Stub the endgames — record, never exec/attach.
__proj_ensure_session() { print -r -- "ensure:$1|$2|$3|${4:-}" >> "$TMP/log"; }
__proj_attach_exec()    { print -r -- "attach:$1|$2" >> "$TMP/log"; }
__proj_launch()         { print -r -- "launch:$1|$2|$3|${4:-}" >> "$TMP/log"; }
tmux() { return 1; }

echo "── pt <work> inside a project dir ──"
: > "$TMP/log"; unset TMUX
( cd "$TMP/GitHub/repo-a" && pt nfl-4 ) >/dev/null 2>&1
ok "ensure + exec attach, named session" \
   "ensure:proj-repo-a|repo-a/nfl-4|$TMP/GitHub/repo-a|
attach:proj-repo-a|repo-a/nfl-4" "$(cat "$TMP/log")"

echo "── pt <project> <work> from anywhere ──"
: > "$TMP/log"
( cd "$TMP" && pt repo-a nfl-5 ) >/dev/null 2>&1
ok "explicit project resolves" \
   "ensure:proj-repo-a|repo-a/nfl-5|$TMP/GitHub/repo-a|
attach:proj-repo-a|repo-a/nfl-5" "$(cat "$TMP/log")"

echo "── pt --claude passes the agent through ──"
: > "$TMP/log"
( cd "$TMP/GitHub/repo-a" && pt --claude nfl-6 ) >/dev/null 2>&1
ok "agent recorded" \
   "ensure:proj-repo-a|repo-a/nfl-6|$TMP/GitHub/repo-a|claude
attach:proj-repo-a|repo-a/nfl-6" "$(cat "$TMP/log")"

echo "── pt refuses bad or missing names ──"
: > "$TMP/log"
( cd "$TMP/GitHub/repo-a" && pt "bad name" ) >/dev/null 2>&1
ok "invalid name: nothing launched" "" "$(cat "$TMP/log")"
( cd "$TMP" && pt ) >/dev/null 2>&1
ok "no args outside a project: nothing launched" "" "$(cat "$TMP/log")"

echo "── pt inside tmux uses launch (switch, not exec) ──"
: > "$TMP/log"; export TMUX="fake,1,0"
( cd "$TMP/GitHub/repo-a" && pt nfl-7 ) >/dev/null 2>&1
ok "launch path inside tmux" \
   "launch:proj-repo-a|repo-a/nfl-7|$TMP/GitHub/repo-a|" "$(cat "$TMP/log")"
unset TMUX

echo "── auto-join hands the project to proj ──"
# Run in a fresh INTERACTIVE zsh (-i satisfies the $- guard) with stubs.
autojoin() {  # $1 = extra env setup, $2 = cwd
  zsh -fi -c "
    export HOME='$TMP'   # a real ~/.no-auto-tmux must not skew the test
    source '$REPO/config/zsh/03-proj-roots.zsh'
    source '$REPO/config/zsh/04-aliases.zsh'
    unalias -m '*' 2>/dev/null
    proj() { print -r -- \"proj:\$*\" >> '$TMP/log'; }
    $1
    cd '$2'
    source '$REPO/config/zsh/06-tmux-autojoin.zsh'
  " >/dev/null 2>&1
}
: > "$TMP/log"
autojoin 'unset TMUX' "$TMP/GitHub/repo-a"
ok "proj called with the project" "proj:repo-a" "$(cat "$TMP/log")"
: > "$TMP/log"
autojoin 'unset TMUX; export AUTO_CLAUDE=1' "$TMP/GitHub/repo-a"
ok "AUTO_CLAUDE adds --claude" "proj:--claude repo-a" "$(cat "$TMP/log")"
: > "$TMP/log"
autojoin 'export TMUX=fake,1,0' "$TMP/GitHub/repo-a"
ok "inside tmux: untouched" "" "$(cat "$TMP/log")"
: > "$TMP/log"
autojoin 'unset TMUX' "$TMP"
ok "outside a project: untouched" "" "$(cat "$TMP/log")"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
```

- [ ] **Step 2: Run to verify it fails**

Run: `zsh tests/pt-autojoin.test.zsh`
Expected: FAIL throughout — pt still numbers slots, `__proj_attach_exec` doesn't exist, auto-join still mints sessions.

- [ ] **Step 3: Rewrite pt() and the auto-join tail**

3a. Replace `pt()` and its comment block in `config/zsh/04-aliases.zsh` with:

```zsh
# Project Tab — create-or-attach a NAMED work session from the shell, with
# the standard layout. The session name is <project>/<work> — same identity
# rule as the proj picker; pt is just the no-picker path for when you
# already know the name.
#
# Usage:
#   pt nfl-4              # work "nfl-4" in the project containing $PWD
#   pt repo-a nfl-4       # explicit project, from anywhere
#   pt --claude nfl-4     # auto-launch Claude in the left pane
#   pt --cursor nfl-4     # auto-launch Cursor in the left pane
pt() {
  local auto_agent=""
  while [[ "$1" == "--claude" || "$1" == "--cursor" ]]; do
    [[ "$1" == "--claude" ]] && auto_agent="claude"
    [[ "$1" == "--cursor" ]] && auto_agent="cursor"
    shift
  done

  if ! __proj_load_roots; then
    echo "No project roots configured. Run \`proj\` to set them up." >&2
    return 1
  fi

  local project="" work=""
  if (( $# >= 2 )); then
    project="$1"; work="$2"
  elif (( $# == 1 )); then
    work="$1"
    project=$(__proj_name_for_dir "$PWD")
  fi
  if [[ -z "$project" || -z "$work" ]]; then
    echo "usage: pt [--claude|--cursor] [<project>] <work>    (project auto-detected inside one)" >&2
    return 1
  fi
  __proj_valid_work "$work" \
    || { echo "invalid work name: $work (allowed: letters digits - _)" >&2; return 1; }

  local proj_dir
  if ! proj_dir=$(__proj_dir_for_name "$project"); then
    echo "project not found: $project" >&2
    return 1
  fi

  local srv name
  srv=$(__proj_srv "$project")
  name="$project/$work"
  if [[ -n "$TMUX" ]]; then
    __proj_launch "$srv" "$name" "$proj_dir" "$auto_agent"
  else
    __proj_ensure_session "$srv" "$name" "$proj_dir" "$auto_agent"
    __proj_attach_exec "$srv" "$name"
  fi
}

# exec-attach endgame for pt outside tmux (factored so tests can stub the
# exec away). `exec` makes detach close the Ghostty tab cleanly.
__proj_attach_exec() { exec tmux -L "$1" attach -t "=$2"; }
```

3b. In `config/zsh/06-tmux-autojoin.zsh`, replace everything after the `proj_name` detection (from the `local srv; srv=$(__proj_srv "$proj_name")` line through the closing `exec tmux … attach` of the slot loop, lines ~48–99) with:

```zsh
  # ⌘T in a project dir: never mint an anonymous session. Open the
  # project's Screen 2 (live sessions · home base · new work) and let the
  # operator name what they're starting — naming is always an explicit
  # gesture. AUTO_CLAUDE=1 keeps its meaning: a session created from this
  # picker auto-launches Claude in the left pane.
  if [[ -n "${AUTO_CLAUDE:-}" ]]; then
    proj --claude "$proj_name"
  else
    proj "$proj_name"
  fi
}
```

Also update the file's header comment (lines 1–21): the behavior list becomes — skips inside tmux / with NO_AUTO_TMUX / outside project roots; otherwise opens proj's Screen 2 for the detected project. Delete the sentences about `<project>-N` slots and the main-session existence check.

- [ ] **Step 4: Run to verify it passes**

Run: `zsh tests/pt-autojoin.test.zsh`
Expected: `PASS=10 FAIL=0`, exit 0. Also re-run `zsh tests/proj-picker.test.zsh` (04-aliases.zsh is shared).

- [ ] **Step 5: Commit**

```bash
git add config/zsh/04-aliases.zsh config/zsh/06-tmux-autojoin.zsh tests/pt-autojoin.test.zsh
git commit -m "feat(proj): pt takes a work name; auto-join opens Screen 2 instead of minting slots"
```

---

### Task 5: titles dedupe, ⚠ primary cue removal, docs

**Files:**
- Modify: `.tmux.conf` (set-titles-string, line 76, and its comment lines 72–75)
- Modify: `tests/set-titles-string.test.zsh` (add cases)
- Modify: `bin/tmux-git-status.sh` (delete the ⚠ primary block, lines ~31–44)
- Modify: `README.md` (proj overview ~48–73, naming-contract section ~177 onward)
- Modify: `docs/terminal-usage.md` (Screen-2 table and worktree doctrine)

**Interfaces:** display + prose only; consumes the `@claude_task` subtitle semantics from Task 2.

- [ ] **Step 1: Add the failing title cases**

In `tests/set-titles-string.test.zsh`, before the final print block:

```zsh
echo "── subtitle/name dedupe (session-identity era) ──"
# @claude_task is now a display-only subtitle mirroring Claude's current
# name; when it equals the session name it must not render twice.
ok "topic equal to session name dropped" "workspace-3" \
   "$(render '' workspace-3 '' '')"
ok "topic equal to name, alias claimed"  "@durable-alias" \
   "$(render durable-alias workspace-3 '' '')"
```

Run: `zsh tests/set-titles-string.test.zsh` — expect exactly these two cases FAIL ("workspace-3 · workspace-3").

- [ ] **Step 2: Extend the title guard**

In `.tmux.conf` line 76, replace the set-titles-string with (one line — only the `@claude_task` conditional gains the `!=,#S` arm):

```tmux
set -g set-titles-string '#{?@claude_attn,🔔 ,}#{?#{&&:#{@muster_agent},#{!=:#{@muster_agent},#S}},@#{@muster_agent},#S}#{?#{&&:#{@claude_task},#{&&:#{!=:#{@claude_task},#{@muster_agent}},#{!=:#{@claude_task},#S}}}, · #{@claude_task},}#{?@muster_inbox, · 📬#{@muster_inbox},}'
```

Update the comment above it (lines 72–75): the topic is `@claude_task`, the display-only subtitle written by statusline.sh (Claude's current name/topic), suppressed when it merely repeats the alias or the session name.

Run: `zsh tests/set-titles-string.test.zsh` — all cases PASS.

- [ ] **Step 3: Remove the ⚠ primary cue**

In `bin/tmux-git-status.sh`, delete the primary-clone warning block (comment lines ~31–39 and the `case`-arm logic setting `wt_flag`, ~40–44) plus the `wt_flag` interpolation where the status string is assembled. Rationale for the log: the cue said "editing the shared tree while worktrees exist — go work in a worktree"; under session-identity doctrine every operator session lives in the primary clone and AGENTS isolate themselves, so the cue would nag on every normal session (the harness's `.claude/worktrees/*` count as linked worktrees).

- [ ] **Step 4: Rewrite the docs**

4a. `README.md` — replace the proj overview paragraph (~48–57) with:

```markdown
One **project workspace = one Ghostty window**. `proj` is a two-screen
picker: Screen 1 picks a project (or jumps to a live session); Screen 2
picks a session — or names new work. **The session name is the identity**:
sessions are born `<project>/<work>` (home base: bare `<project>`), every
surface aligns to that name, and renames go through one gesture
(`prefix T`) so no surface is left behind. Isolation is the agent's job —
proj opens everything in the primary clone and coding agents make their
own worktrees when they need them.
```

Update the command table rows (~60–66): `proj` → "two-screen picker → jump to a session, open the home base, or name new work"; add `proj <project>` → "skip Screen 1"; `pt <work>` / `pt <project> <work>` → "create-or-attach `<project>/<work>` without the picker"; delete any worktree wording. Delete the sentence at ~72–73 pointing at "the full worktree workflow".

4b. `README.md` — replace the `### The naming contract (tmux ↔ muster)` section (from the heading through the `@claude_task_promoted` paragraph) with:

```markdown
### The naming contract (tmux ↔ muster)

The tmux session name (`#S`) is the identity (spec:
`docs/superpowers/specs/2026-08-08-proj-session-identity-design.md`). A
session is born named for its work (`<project>/<work>`, via the proj
picker or `pt`), and every surface aligns to that one name: tab titles,
the picker, and — when muster is installed — the bus alias, which its
SessionStart hook seeds from the session name.

Renames go through one gesture so no surface is left behind. `prefix T`
(`bin/tmux-session-rename.sh`) validates the name (letters, digits, `-`,
`_`, `/`), refuses names any live session holds, renames the tmux
session, and — with muster — calls `muster become`, which claims the
alias on the bus (mail follows via lineage) and types `/rename` into the
registered Claude pane. `/rename` inside Claude flows the other way: the
statusline proves the name is user-set via the transcript custom-title
record, then renames the tmux session (plus `muster become --no-inject`
when available — the name already came from `/rename`). Without muster,
both gestures still work, just tmux-only.

`@claude_task` survives as a display-only subtitle — whatever Claude
currently calls the conversation (usually its auto topic), rendered in
the title's middle segment and deduped against the session name. It
never renames anything. `@claude_task_promoted` records the last title
the statusline acted on, so a stale transcript title (a swallowed
`/rename`) can't revert an operator's rename. `@claude_task_manual` is
retired.
```

4c. `docs/terminal-usage.md` — replace the Screen-2 table and its intro (~80–94) with:

```markdown
   **Screen 2 — pick a session, or name new work.**

   | Row | What it does |
   |---|---|
   | `● <project>/<work>  — <topic>` | Jump to a live session. The suffix is Claude's current subtitle (`@claude_task`). |
   | `🏠 <project> — home base (primary clone)` | Open the home-base session — reading & coordinating. |
   | `+ new work…` | Prompts for a work name (letters digits `-` `_`), then creates `<project>/<work>` in the primary clone. |
```

Replace the worktree-doctrine content (~17–23, 36–39, 101–108) with:

```markdown
Sessions are named for their work and live in the primary clone. Coding
agents create their own worktrees when they need isolation — those are
the agent's to manage, and the picker never touches them.
```

Keep the minimal-docs rule: delete, don't rephrase, anything describing machinery that no longer exists (`.worktreeinclude`, pruning, `<project>-N` slots, branch rows). Update the session-name row of the vocabulary table (~36) to `<project>` (home base) / `<project>/<work>` (named work).

- [ ] **Step 5: Run every test, then commit**

```bash
for t in tests/*.test.zsh; do echo "== $t"; zsh "$t" || break; done
```
Expected: every file ends `FAIL=0` / "0 failed".

```bash
git add .tmux.conf tests/set-titles-string.test.zsh bin/tmux-git-status.sh README.md docs/terminal-usage.md
git commit -m "feat(titles,docs): subtitle/name dedupe, retire the primary-clone cue, session-identity docs"
```

---

### Task 6: coordinate the muster half over the bus

**Files:** none (bus message only).

**Interfaces:**
- Consumes: the muster MCP tools (`mcp__muster__send_message`), sender alias `dotfiles-2`.
- Produces: the contract proposal thread the muster repo's agent implements against.

- [ ] **Step 1: Send the proposal to durable-alias**

Send via the muster `send_message` tool — from `dotfiles-2`, to agent `durable-alias`, subject `contract change: the session name IS the identity (proj realignment)`, ref `~/dotfiles/docs/superpowers/specs/2026-08-08-proj-session-identity-design.md`, body:

```
Operator-approved contract change, dotfiles half implemented on a feature
branch (spec in ref). The tmux↔muster meeting point moves from the
@claude_task/@claude_task_manual pair to the SESSION NAME (#S). proj now
creates sessions named <project>/<work> (no more numbered slots), so your
SessionStart hook's alias = session-name seed makes aliases born
meaningful with zero changes on your side.

Division of labor for renames — dotfiles owns the tmux rename; muster owns
the bus + injection:

1. Operator CLI `muster become <name>` (resolving the session from
   $TMUX_PANE like `muster label` does): claim the alias for this session
   (lineage-following mail, as become does today) and type
   `/rename <name>` into the registered live Claude pane. It does NOT need
   to rename the tmux session — prefix T's shim
   (bin/tmux-session-rename.sh) has already done that, validated
   [A-Za-z0-9_/-] and refused live collisions, before calling you.
2. `muster become --no-inject <name>` — same minus the injection, called
   by the statusline when the name came FROM /rename (re-typing would
   loop). Same shape as label --no-inject.
3. Your filed seed-collision follow-up (thread 154) covers the hook path;
   nothing new needed there from us.
4. Deprecate `muster label` as the human-handle concept when convenient:
   @claude_task is now a display-only subtitle written by our statusline;
   @claude_task_manual has no writers left in dotfiles. Please stop
   writing/reading the manual flag whenever you touch that code.
5. Confirm the alias charset accepts '/'. proj's old <project>/<branch>
   session names were seeded for months, so we expect yes — say if not,
   and we'll switch the join character before shipping.

No urgency coupling: our shim and statusline probe `muster become --help`
and degrade to tmux-only renames until your CLI lands, so both repos ship
independently. Reply with the CLI shape when it lands (or objections to
any of the above) and we'll do the joint smoke: prefix-T rename with mail
in flight → alias follows with inbox intact; /rename inside Claude →
#S follows, no injection loop.
```

- [ ] **Step 2: Note the interim behavior in the PR/branch log**

Until muster ships the `become` CLI surface: prefix T and statusline renames are tmux-only (probe fails); the bus alias keeps the birth name. Mail still routes (alias unchanged); the alias catches up when muster lands and the operator re-runs the gesture. This is the accepted degradation from the spec's independence guarantee — record it in the branch's final commit message or PR description so the joint smoke test isn't forgotten.

---

## Final verification (after all tasks)

- [ ] Full suite: `for t in tests/*.test.zsh; do echo "== $t"; zsh "$t" || break; done` — all green.
- [ ] Manual smoke (operator gates): `proj` → pick a project → `+ new work…` → name lands as `<project>/<work>` with the standard layout; `prefix T` rename → title, picker, and (once muster lands) `muster agents` all show the new name with inbox intact; `/rename check-flow` inside Claude → `#S` follows within one statusline tick; PATH-stripped run (`PATH=/usr/bin:/bin`) of both gestures stays functional.
- [ ] Merge via the repo's usual flow (feature branch → main), then delete the worktree.

## Spec-coverage map

§2 naming model → Tasks 1–3, 5. §3 picker/pt/auto-join → Tasks 3–4. §4 rename gesture → Tasks 1–2. §5 muster coordination → Task 6 (+ probes in 1–2). §6 migration → legacy-name rows in Task 3's `__proj_session_list`; README rewrite in Task 5. §7 testing → each task's test file + final sweep. The ⚠ primary cue removal (Task 5, Step 3) is the one change beyond the spec's letter — it implements §3's "isolation is the agent's job" doctrine on the status bar; flagged to the operator in the plan summary.
