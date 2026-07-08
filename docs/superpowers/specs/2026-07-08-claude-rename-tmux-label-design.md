# Claude Code session rename → tmux task label

## Problem

Renaming a Claude Code session (`/rename foo` or `claude --name foo`) gives
the session a meaningful name inside Claude, but the surrounding tmux
session still shows only `<project>-N` in the status bar, Ghostty tab,
Dock, ⌘-Tab, and the proj picker. The task-label system from
`2026-06-11-tmux-session-labels-design.md` covers those surfaces, but the
label must be typed a second time via `prefix T`.

## Solution

When Claude Code reports a custom session name, automatically copy it into
the tmux session's `@claude_task` option — the label that already flows to
every display surface. tmux session **names** remain immutable, as required
by the earlier spec (`proj`, auto-join, and tmux-resurrect key off
`<project>-N`).

### Mechanism: statusline intercept

`config/claude/statusline.sh` already runs on every Claude Code status
update and already writes per-pane state for tmux. Claude's statusline
stdin JSON carries a `session_name` field that is present exactly when a
custom name has been set (via `/rename` or `--name`); auto-derived names
(e.g. `dotfiles-e7`) never appear there.

New logic in `statusline.sh`, active only when `$TMUX_PANE` is set:

1. Parse `session_name` from the stdin JSON (`.session_name // ""`).
2. If empty → do nothing (see "set, never clear" below).
3. Read the current label: `tmux show-option -qv -t "$TMUX_PANE" @claude_task`.
4. If it differs, `tmux set-option -t "$TMUX_PANE" @claude_task "$name"`
   followed by `refresh-client -S`.

Because statusline.sh inherits `$TMUX` from the Claude process, the tmux
calls automatically reach the correct per-project tmux server — no `-L`
socket handling needed. `-t "$TMUX_PANE"` resolves to the pane's session
for session-scoped options.

### Behavioral rules

- **Set, never clear.** The label is only written when `session_name` is
  present and different from the current label. A Claude session without a
  custom name never touches the label, so manual `prefix T` labels survive.
  A later rename overwrites whatever label is there (rename wins).
- **Derived names don't propagate.** Only deliberate renames appear in
  `session_name`, keeping the earlier spec's rejection of automatic
  labeling intact.
- **Manual override stays available.** `prefix T` continues to work; it and
  the auto-set simply write the same option, last writer wins.

## Edge cases

- **Multiple named Claude panes in one tmux session** (e.g. agent panes):
  last writer wins. Acceptable — agent panes get derived names, which never
  propagate, so in practice only the main pane writes.
- **Names with quotes/spaces:** the name is passed to tmux as a single
  quoted shell argument from bash; no re-parsing occurs.
- **Outside tmux:** guarded by the existing `$TMUX_PANE` check; no change
  to the non-tmux statusline output.
- **Cost:** one `tmux show-option` per statusline refresh, plus a
  `set-option` only on change. Negligible.

## Files touched

- `config/claude/statusline.sh` — parse `session_name`, sync to
  `@claude_task` (only file that changes).

## Out of scope

- Renaming actual tmux sessions (breaks proj/auto-join/resurrect keying).
- Clearing the label when a Claude session ends or its name is removed.
- Propagating auto-derived session names.
- A rename in the other direction (prefix T → Claude session name).
