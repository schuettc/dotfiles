# Claude Rename → tmux Task Label Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a Claude Code session gets a custom name (`/rename` or `--name`), automatically copy it into the tmux session's `@claude_task` label.

**Architecture:** `config/claude/statusline.sh` (already invoked by Claude Code on every status update, already tmux-aware via `$TMUX_PANE`) parses the `session_name` field from its stdin JSON and, when present and different from the current label, writes it to the session-scoped `@claude_task` tmux option. All display surfaces (status-left, Ghostty tab titles, proj picker) already render `@claude_task`, so no other file changes.

**Tech Stack:** bash, jq, tmux. No test framework exists in this repo — verification is a scripted check against a scratch tmux server (throwaway socket `-L renametest`, never the real per-project servers).

**Spec:** `docs/superpowers/specs/2026-07-08-claude-rename-tmux-label-design.md`

## Global Constraints

- tmux session **names** must never be changed — only the `@claude_task` session option.
- **Set, never clear:** empty/absent `session_name` must leave the existing label untouched.
- All tmux calls must go through the plain `tmux` binary with the inherited `$TMUX` env (no `-L` socket flags in statusline.sh) so they reach the correct per-project server.
- All new tmux calls must be best-effort (`2>/dev/null`) — statusline.sh must never break the status line if tmux misbehaves.

---

### Task 1: Sync `session_name` → `@claude_task` in statusline.sh

**Files:**
- Modify: `config/claude/statusline.sh` (add a block after the state-file write, before the "Print the in-Claude status line" section; also extend the header comment)

**Interfaces:**
- Consumes: statusline stdin JSON field `.session_name` (present only when a custom name is set); env `$TMUX_PANE`, `$TMUX`.
- Produces: tmux session option `@claude_task` on the pane's session (same option `prefix T` writes; rendered by `.tmux.conf` status-left, `set-titles-string`, and the proj picker).

- [ ] **Step 1: Write the failing verification script**

Create `/private/tmp/claude-501/-Users-courtschuett-dotfiles/035a4846-0ea0-4083-a8fa-c0577b588387/scratchpad/test-rename-label.sh` (scratchpad — not committed):

```bash
#!/bin/bash
# Verify statusline.sh syncs session_name → @claude_task on a scratch tmux server.
set -u
SL="$HOME/dotfiles/config/claude/statusline.sh"
SRV=renametest
fail=0

tmux -L "$SRV" kill-server 2>/dev/null
tmux -L "$SRV" new-session -d -s t1
pane=$(tmux -L "$SRV" list-panes -t t1 -F '#{pane_id}' | head -1)
sock=$(tmux -L "$SRV" display-message -p '#{socket_path}')

run_sl() {  # $1 = JSON payload
  printf '%s' "$1" | TMUX="${sock},0,0" TMUX_PANE="$pane" bash "$SL" >/dev/null
}

label() { tmux -L "$SRV" show-option -qv -t t1 @claude_task; }

# Case 1: session_name present → label set
run_sl '{"session_name":"my-task","model":{"display_name":"Fable"},"context_window":{"used_percentage":10},"workspace":{"current_dir":"/tmp"}}'
[[ "$(label)" == "my-task" ]] || { echo "FAIL case1: label='$(label)' want 'my-task'"; fail=1; }

# Case 2: session_name absent → existing label untouched (set-never-clear)
run_sl '{"model":{"display_name":"Fable"},"context_window":{"used_percentage":10},"workspace":{"current_dir":"/tmp"}}'
[[ "$(label)" == "my-task" ]] || { echo "FAIL case2: label='$(label)' want 'my-task' (must not clear)"; fail=1; }

# Case 3: rename again → label overwritten
run_sl '{"session_name":"other-task","model":{"display_name":"Fable"},"context_window":{"used_percentage":10},"workspace":{"current_dir":"/tmp"}}'
[[ "$(label)" == "other-task" ]] || { echo "FAIL case3: label='$(label)' want 'other-task'"; fail=1; }

# Case 4: name with spaces survives quoting
run_sl '{"session_name":"fix tmux labels","model":{"display_name":"Fable"},"context_window":{"used_percentage":10},"workspace":{"current_dir":"/tmp"}}'
[[ "$(label)" == "fix tmux labels" ]] || { echo "FAIL case4: label='$(label)' want 'fix tmux labels'"; fail=1; }

tmux -L "$SRV" kill-server 2>/dev/null
(( fail == 0 )) && echo "ALL PASS"
exit "$fail"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /private/tmp/claude-501/-Users-courtschuett-dotfiles/035a4846-0ea0-4083-a8fa-c0577b588387/scratchpad/test-rename-label.sh`
Expected: `FAIL case1: label='' want 'my-task'` (and case3/case4 failures), exit 1 — statusline.sh doesn't touch `@claude_task` yet.

- [ ] **Step 3: Implement the sync block in statusline.sh**

In `config/claude/statusline.sh`, insert between the "Write state file for tmux status bar" block (ends line 42) and the "Print the in-Claude status line" section (starts line 44):

```bash
# ─── Sync Claude session rename → tmux task label ────────────────────
# Claude includes `session_name` in the statusline JSON only when the
# session has a custom name (/rename or --name); auto-derived names
# never appear here. Copy it into the session-scoped @claude_task
# option — the same label `prefix T` sets — so a rename shows up in
# status-left, Ghostty tab titles, and the proj picker automatically.
# Set-never-clear: an unnamed session leaves manual labels alone.
# Plain `tmux` + inherited $TMUX reaches the right per-project server.
SESSION_NAME=$(echo "$input" | jq -r '.session_name // ""')
if [[ -n "$SESSION_NAME" && -n "${TMUX_PANE:-}" ]]; then
  current_label=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task 2>/dev/null)
  if [[ "$SESSION_NAME" != "$current_label" ]]; then
    tmux set-option -t "$TMUX_PANE" @claude_task "$SESSION_NAME" 2>/dev/null
    tmux refresh-client -S 2>/dev/null
  fi
fi
```

Also update the header comment's responsibility list (lines 4–12): after the item describing the per-pane state file, add:

```bash
#   3. Sync a custom Claude session name (/rename) into the tmux
#      session's @claude_task label so it shows on every surface.
```

(Renumber: the two existing responsibilities are `1.` and `2.`; this becomes `3.`)

- [ ] **Step 4: Run the verification script to verify it passes**

Run: `bash /private/tmp/claude-501/-Users-courtschuett-dotfiles/035a4846-0ea0-4083-a8fa-c0577b588387/scratchpad/test-rename-label.sh`
Expected: `ALL PASS`, exit 0.

If case1 fails with an empty label but no error, check `tmux show-option`/`set-option` accept a pane id (`%0`) as `-t` on the installed tmux version: `tmux -V`, then `tmux -L renametest set-option -t "$pane" @x 1`. If the pane target is rejected, resolve the session explicitly first: `sess=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}')` and use `-t "$sess"` in both calls.

- [ ] **Step 5: Sanity-check the real statusline path is unchanged outside tmux**

Run: `printf '%s' '{"session_name":"x","model":{"display_name":"Fable"},"context_window":{"used_percentage":10},"workspace":{"current_dir":"/tmp"}}' | bash ~/dotfiles/config/claude/statusline.sh`
Expected: prints `Fable · tmp` and exits 0 (no tmux calls attempted, no errors — `$TMUX_PANE` unset).

- [ ] **Step 6: Commit**

```bash
git add config/claude/statusline.sh
git commit -m "feat(claude): sync session rename into tmux @claude_task label"
```

---

### Task 2: Live end-to-end verification (manual, with the user)

**Files:** none (verification only)

**Interfaces:**
- Consumes: the deployed `statusline.sh` (Task 1) — confirm `~/.config/claude/statusline.sh` resolves to the repo file (it's a symlink/managed copy; check with `ls -la ~/.config/claude/statusline.sh`).

- [ ] **Step 1: Confirm the deployed script is the repo file**

Run: `ls -la ~/.config/claude/statusline.sh`
Expected: symlink into `~/dotfiles/config/claude/statusline.sh` (or identical content via `diff`). If it's a stale copy, re-run the dotfiles install/update script the repo uses (`./update.sh`).

- [ ] **Step 2: Ask the user to rename a live session**

In any tmux-hosted Claude Code session, run `/rename smoke-test-label`, then send one message (statusline updates on activity). Expected within a moment: status-left shows `smoke-test-label` in lavender after the session name, and the Ghostty tab shows `<session> · smoke-test-label`. The tmux session name itself (e.g. `dotfiles-2`) is unchanged in `tmux list-sessions`.

- [ ] **Step 3: Confirm manual labels still work**

`prefix T`, type `manual-label`. Expected: label changes to `manual-label` and stays until the next `/rename`.
