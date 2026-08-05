# Naming Contract (dotfiles half) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/rename` inside Claude becomes a first-class naming gesture (promoted to a manual, addressable label via the transcript custom-title record), and prefix T works without muster installed — while the muster path, including its `/rename` injection, stays byte-for-byte as today.

**Architecture:** Companion to the muster-repo plan `~/GitHub/schuettc/muster/docs/superpowers/plans/2026-08-05-conversation-identity-naming.md` (spec: `.../specs/2026-08-05-conversation-identity-naming-design.md` there). Two independent changes: (1) `config/claude/statusline.sh`'s name-sync block learns to distinguish a user-set name (the transcript carries a `{"type":"custom-title"}` record whose `customTitle` equals the current `session_name`) from an auto topic, and promotes the former to a manual label — via `muster label --no-inject` when muster is installed, plain `tmux set-option` otherwise; auto topics keep today's display-only, defer-to-manual behavior. (2) `bin/tmux-muster-label.sh` (the prefix-T shim) gets a muster-less fallback: plain option writes, no send-keys. The tmux option pair `@claude_task` / `@claude_task_manual` is the contract: intentional gestures set both, automatic syncs write only the label and defer to the flag.

**Tech Stack:** zsh/bash scripts; tests are standalone `tests/*.test.zsh` files run directly (`zsh tests/<name>.test.zsh`), using a real throwaway tmux server (`tmux -S <tmpdir>/sock`) and the repo's `ok()` PASS/FAIL convention (copy the prelude from `tests/set-titles-string.test.zsh`).

## Global Constraints

- **PREREQUISITE:** the statusline task requires `muster label --no-inject` (muster plan Task 5) in the installed binary. Run `muster label --help 2>&1 | grep -q no-inject` before starting Task 2; if absent, build/install muster from its feature branch first.
- **Non-regression (operator-confirmed 2026-08-05):** with muster installed, prefix T must keep typing `/rename <name>` into the Claude pane exactly as today. Nothing in this plan may touch that path's behavior.
- The statusline must never *demote*: no code path may clear `@claude_task_manual` or overwrite a manual label with an auto topic.
- No send-keys anywhere in this repo's naming scripts — typing into panes is muster's job (its nudge path handles liveness); the muster-less fallback aligns tmux only.
- Statusline runs on every render tick: the promotion path must have a cheap fast-path that skips the transcript read once label and flag are already aligned.

---

### Task 1: prefix-T shim works without muster

**Files:**
- Modify: `bin/tmux-muster-label.sh`
- Create: `tests/tmux-muster-label.test.zsh`

**Interfaces:**
- Consumes: tmux option pair `@claude_task` / `@claude_task_manual` (the contract); `muster label` CLI when present.
- Produces: the shim's observable behavior — muster present: unchanged delegation; muster absent: label + manual flag set (or both unset on clear) via plain tmux, feedback via `display-message`.

- [ ] **Step 1: Write the failing test**

`tests/tmux-muster-label.test.zsh` (prelude — `set -u`, `REPO="${0:A:h:h}"`, `ok()`, tmux-required guard — copied from `tests/set-titles-string.test.zsh`):

```zsh
# Tests for bin/tmux-muster-label.sh: the prefix-T shim must work with AND
# without muster on PATH (naming-contract plan, 2026-08-05). Real throwaway
# tmux server; a fake `muster` script records delegation.

WORK=$(mktemp -d)
trap 'tmux -S "$WORK/sock" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT
tmux -S "$WORK/sock" new-session -d -s t -x 80 -y 24
PANE=$(tmux -S "$WORK/sock" display-message -p -t t '#{pane_id}')
export TMUX="$WORK/sock,999,0"

opt()    { tmux -S "$WORK/sock" show-option -qv -t t @claude_task; }
manual() { tmux -S "$WORK/sock" show-option -qv -t t @claude_task_manual; }

# ── muster ABSENT: plain-tmux fallback ──────────────────────────────
print '── fallback (no muster) ──'
PATH_SAVE="$PATH"
export PATH="/usr/bin:/bin"   # strip muster (and everything else non-core)
"$REPO/bin/tmux-muster-label.sh" "$PANE" "nfl-3"
ok "fallback sets label"        "nfl-3" "$(opt)"
ok "fallback sets manual flag"  "1"     "$(manual)"
"$REPO/bin/tmux-muster-label.sh" "$PANE" ""
ok "fallback clear unsets label"  "" "$(opt)"
ok "fallback clear unsets manual" "" "$(manual)"
export PATH="$PATH_SAVE"

# ── muster PRESENT: delegation, args recorded ───────────────────────
print '── delegation (fake muster) ──'
mkdir -p "$WORK/bin"
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
echo "labeled"
EOF
chmod +x "$WORK/bin/muster"
export PATH="$WORK/bin:$PATH" MUSTER_ARGS_LOG="$WORK/args.log"
"$REPO/bin/tmux-muster-label.sh" "$PANE" "nfl-3"
ok "delegates to muster label" "label nfl-3" "$(tail -1 "$WORK/args.log")"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
```

- [ ] **Step 2: Run to verify it fails**

Run: `zsh tests/tmux-muster-label.test.zsh`
Expected: FAIL — the current shim hardcodes `$HOME/.local/bin/muster`, so the fallback cases error (`muster label FAILED` display) and set nothing, and the fake-muster case never sees the delegation.

- [ ] **Step 3: Rewrite the shim**

```bash
#!/bin/bash
# prefix T handler: one naming gesture for tmux, the bus, and the agent
# harness (naming-contract plan 2026-08-05; spec in the muster repo).
#
# With muster on PATH, delegate to `muster label`: tmux option pair + bus
# sync + typing /rename into the live Claude pane — KEEP AS-IS, the
# injection is operator-confirmed working well. Without muster, fall back to
# the plain tmux half of the contract: label + manual flag (both unset on
# clear). No send-keys in the fallback — typing into panes is muster's job.
#
# tmux run-shell children inherit $TMUX but NOT $TMUX_PANE, and muster's
# ambient tmux calls resolve the current session through the pane — without
# this shim the label half-writes against whatever session tmux guesses.
# $1 is #{pane_id}, expanded by the binding at press time; $2 is the label
# (empty = clear). Output goes to a status-line display-message: run-shell
# opens a full-screen view for ANY stdout, which reads as an error screen
# instead of feedback.
export TMUX_PANE="$1"
shift

if command -v muster >/dev/null 2>&1; then
  if out=$(muster label "$@" 2>&1); then
    tmux display-message "muster: ${out//$'\n'/ · }"
  else
    tmux display-message "muster label FAILED: ${out//$'\n'/ · }"
  fi
  exit 0
fi

# muster-less fallback: the tmux half of the naming contract only.
if [[ -n "${1:-}" ]]; then
  tmux set-option -t "$TMUX_PANE" @claude_task "$1"
  tmux set-option -t "$TMUX_PANE" @claude_task_manual 1
  tmux refresh-client -S
  tmux display-message "label: $1 (tmux only — muster not installed)"
else
  tmux set-option -u -t "$TMUX_PANE" @claude_task
  tmux set-option -u -t "$TMUX_PANE" @claude_task_manual
  tmux refresh-client -S
  tmux display-message "label cleared (tmux only — muster not installed)"
fi
```

Note the one deliberate behavior change on the muster path: `command -v muster` instead of the hardcoded `$HOME/.local/bin/muster`. The dotfiles muster package installs there and it's on PATH, so resolution is identical in practice — but confirm `echo "$PATH" | tr : '\n' | grep -qx "$HOME/.local/bin"` in your shell before shipping; if tmux run-shell's PATH lacks it, keep a two-step resolve: `MUSTER_BIN=$(command -v muster || { [[ -x "$HOME/.local/bin/muster" ]] && echo "$HOME/.local/bin/muster"; })` and branch on `-n "$MUSTER_BIN"`.

- [ ] **Step 4: Run to verify it passes**

Run: `zsh tests/tmux-muster-label.test.zsh`
Expected: `PASS=5 FAIL=0`, exit 0

- [ ] **Step 5: Manual non-regression check (muster path)**

In a real tmux session with a live Claude pane: press `prefix T`, enter a name, and confirm (a) the tab title updates, (b) `/rename <name>` appears in the Claude pane, (c) `muster agents` shows the manual label. This is the operator-confirmed path — it must be indistinguishable from before.

- [ ] **Step 6: Commit**

```bash
git add bin/tmux-muster-label.sh tests/tmux-muster-label.test.zsh
git commit -m "feat(tmux): prefix-T shim works without muster (plain-tmux fallback, no send-keys)"
```

---

### Task 2: statusline promotes user-set names to manual

**Files:**
- Modify: `config/claude/statusline.sh` (the "Sync Claude session name → tmux task label" block, ~lines 61-81)
- Create: `tests/statusline-name-sync.test.zsh`

**Interfaces:**
- Consumes: statusline JSON stdin fields `.session_name` and `.transcript_path` (both verified present, Claude Code 2.1.222); transcript `{"type":"custom-title","customTitle":…}` records (last one wins); `muster label --no-inject <name>` (muster plan Task 5).
- Produces: the contract behavior — user-set name ⇒ label + manual flag (bus-synced when muster present); auto topic ⇒ label only, deferring to the flag; aligned state ⇒ no work, no transcript read.

- [ ] **Step 1: Write the failing test**

`tests/statusline-name-sync.test.zsh` (same prelude/throwaway-tmux scaffolding as Task 1's test; also requires `jq`, guard like the tmux guard):

```zsh
# Tests for statusline.sh's name-sync block: a user-set name (transcript
# custom-title == session_name) is PROMOTED to a manual label; an auto topic
# stays display-only and defers to the manual flag; nothing ever demotes.

WORK=$(mktemp -d)
trap 'tmux -S "$WORK/sock" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT
tmux -S "$WORK/sock" new-session -d -s t -x 80 -y 24
PANE=$(tmux -S "$WORK/sock" display-message -p -t t '#{pane_id}')
export TMUX="$WORK/sock,999,0" TMUX_PANE="$PANE"

opt()    { tmux -S "$WORK/sock" show-option -qv -t t @claude_task; }
manual() { tmux -S "$WORK/sock" show-option -qv -t t @claude_task_manual; }
reset()  { tmux -S "$WORK/sock" set-option -u -t t @claude_task 2>/dev/null
           tmux -S "$WORK/sock" set-option -u -t t @claude_task_manual 2>/dev/null; }

TRANSCRIPT="$WORK/t.jsonl"
statusline() {  # $1 = session_name, $2 = transcript path ("" for none)
  jq -n --arg n "$1" --arg tp "$2" \
    '{model:{display_name:"Fable"},context_window:{used_percentage:10},
      workspace:{current_dir:"/w"},session_name:$n,transcript_path:$tp}' \
    | "$REPO/config/claude/statusline.sh" >/dev/null 2>&1
}

# ── auto topic: display-only (today's behavior, must survive) ───────
reset
printf '%s\n' '{"type":"user"}' > "$TRANSCRIPT"   # no custom-title record
statusline "Debug tmux titles" "$TRANSCRIPT"
ok "auto topic lands in label" "Debug tmux titles" "$(opt)"
ok "auto topic sets NO manual flag" "" "$(manual)"

# ── user-set name, muster absent: plain-tmux promotion ──────────────
reset
printf '%s\n' '{"type":"custom-title","customTitle":"nfl-3","sessionId":"u1"}' > "$TRANSCRIPT"
PATH_SAVE="$PATH"; export PATH="/usr/bin:/bin"
statusline "nfl-3" "$TRANSCRIPT"
export PATH="$PATH_SAVE"
ok "custom title promotes label"  "nfl-3" "$(opt)"
ok "custom title promotes manual" "1"     "$(manual)"

# ── user-set name, muster present: --no-inject delegation ───────────
reset
mkdir -p "$WORK/bin"
cat > "$WORK/bin/muster" <<'EOF'
#!/bin/sh
echo "$@" >> "${MUSTER_ARGS_LOG:?}"
EOF
chmod +x "$WORK/bin/muster"
export PATH="$WORK/bin:$PATH" MUSTER_ARGS_LOG="$WORK/args.log"
statusline "nfl-3" "$TRANSCRIPT"
ok "delegates with --no-inject" "label --no-inject nfl-3" "$(tail -1 "$WORK/args.log")"

# ── never demote: manual flag blocks a later auto topic ─────────────
printf '%s\n' '{"type":"user"}' > "$TRANSCRIPT"   # custom-title gone from a NEW transcript
statusline "Some auto topic" "$TRANSCRIPT"
ok "auto topic never clobbers manual label" "nfl-3" "$(opt)"
ok "manual flag survives"                   "1"     "$(manual)"

# ── fast path: aligned state reads no transcript ────────────────────
rm -f "$MUSTER_ARGS_LOG"
statusline "nfl-3" "$WORK/does-not-exist.jsonl"   # would fail if read mattered
ok "aligned state does nothing" "" "$(cat "$MUSTER_ARGS_LOG" 2>/dev/null)"

print
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
```

- [ ] **Step 2: Run to verify it fails**

Run: `zsh tests/statusline-name-sync.test.zsh`
Expected: the two auto-topic cases PASS (today's behavior); the promotion, delegation, and fast-path cases FAIL.

- [ ] **Step 3: Replace the sync block**

In `config/claude/statusline.sh`, replace the block bounded by the `# ─── Sync Claude session name → tmux task label` header comment and its closing `fi` with:

```bash
# ─── Sync Claude session name → tmux task label ──────────────────────
# Claude ships `session_name` in the statusline JSON whenever the session
# has a name — an explicit /rename (or --name) AND the auto-generated topic
# both land in the same field. The transcript disambiguates (naming-contract
# plan 2026-08-05): a {"type":"custom-title"} record whose customTitle
# equals the current session_name proves the name is USER-SET. User-set →
# PROMOTE: label + @claude_task_manual, bus-synced via `muster label
# --no-inject` when muster is installed (--no-inject because the name
# already CAME from /rename — re-typing it would loop text into the pane).
# Auto topic → display-only, defers to the manual flag (unchanged). Nothing
# here ever demotes. Newest gesture wins: a fresh /rename overwrites a
# stale manual label because its custom-title matches the new session_name.
SESSION_NAME=$(echo "$input" | jq -r '.session_name // ""')
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // ""')
if [[ -n "$SESSION_NAME" && -n "${TMUX_PANE:-}" ]]; then
  is_manual=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task_manual 2>/dev/null)
  current_label=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task 2>/dev/null)
  if [[ "$current_label" == "$SESSION_NAME" && -n "$is_manual" ]]; then
    : # fast path: already promoted and aligned — no transcript read
  else
    custom_title=""
    if [[ -n "$TRANSCRIPT_PATH" && -r "$TRANSCRIPT_PATH" ]]; then
      custom_title=$(grep '"custom-title"' "$TRANSCRIPT_PATH" 2>/dev/null \
        | tail -1 | jq -r '.customTitle // ""' 2>/dev/null)
    fi
    if [[ -n "$custom_title" && "$custom_title" == "$SESSION_NAME" ]]; then
      if command -v muster >/dev/null 2>&1; then
        muster label --no-inject "$SESSION_NAME" >/dev/null 2>&1
      else
        tmux set-option -t "$TMUX_PANE" @claude_task "$SESSION_NAME" 2>/dev/null
        tmux set-option -t "$TMUX_PANE" @claude_task_manual 1 2>/dev/null
      fi
      tmux refresh-client -S 2>/dev/null
    elif [[ -z "$is_manual" && "$SESSION_NAME" != "$current_label" ]]; then
      tmux set-option -t "$TMUX_PANE" @claude_task "$SESSION_NAME" 2>/dev/null
      tmux refresh-client -S 2>/dev/null
    fi
  fi
fi
```

- [ ] **Step 4: Run to verify it passes**

Run: `zsh tests/statusline-name-sync.test.zsh`
Expected: `PASS=8 FAIL=0`, exit 0. Also re-run the repo's other test files touched by nothing (`zsh tests/set-titles-string.test.zsh`) to confirm no shared-state surprises.

- [ ] **Step 5: Live check**

In a real Claude session inside tmux: `/rename check-promotion`, wait one statusline tick, then `tmux show-option -qv @claude_task_manual` → `1`, and `muster agents` shows `check-promotion` as a manual label. Then `/rename` back or `prefix T` your usual name.

- [ ] **Step 6: Commit**

```bash
git add config/claude/statusline.sh tests/statusline-name-sync.test.zsh
git commit -m "feat(statusline): promote user-set session names (transcript custom-title) to manual labels"
```

---

### Task 3: Document the contract

The spec (§5.3) pins the option-pair contract in both repos so they can't drift. Muster's side lands in its CLAUDE.md (muster plan Task 7); this repo has no CLAUDE.md, so its side goes in `README.md` next to the existing muster/tmux wiring documentation.

**Files:**
- Modify: `README.md` (the section documenting the muster package / tmux label wiring — find it via `grep -n "claude_task\|muster" README.md`)

**Interfaces:** none — prose only.

- [ ] **Step 1: Add the contract section**

Insert where the label/statusline wiring is described:

```markdown
### The naming contract (tmux ↔ muster)

The tmux option pair `@claude_task` / `@claude_task_manual` is the neutral
meeting point between this repo and muster (spec:
muster/docs/superpowers/specs/2026-08-05-conversation-identity-naming-design.md).
Intentional gestures — prefix T, `muster label`, a promoted `/rename` (the
transcript custom-title proves intent) — set both options; automatic syncs
(the statusline copying an auto topic) write only the label and defer to the
flag; readers (status-left, tab titles, the proj picker, muster's resolver
via its stored copy) trust the pair. Each side works alone: without muster,
prefix T and the statusline still maintain the pair (display only); with
muster, the same gestures also sync the bus label, making the name
addressable (`muster send <name>`).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: the tmux/muster naming contract"
```

---

## Sequencing with the muster plan

Muster plan Tasks 1–6 (especially Task 5's `--no-inject`) land first and get installed. Task 1 here is independent of muster entirely; Task 2 needs the installed binary. The joint operator-acceptance gate lives at the end of the muster plan: restart tmux, resume a custom-titled conversation, verify zero-gesture alignment and routing, and confirm prefix T still types `/rename`.
