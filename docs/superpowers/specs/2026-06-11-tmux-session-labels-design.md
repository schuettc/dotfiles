# tmux session task labels + per-session name colors

## Problem

Multiple Claude Code sessions run in parallel, one per tmux session
(`workspace`, `workspace-2`, `workspace-3`, …). In the Ghostty tab bar, the
Dock window list, ⌘-Tab, and the `proj` picker they are indistinguishable —
nothing says which one is writing docs vs implementing a feature.

## Solution

A manually set, session-scoped task label, plus a stable per-session color
for the session name in the tmux status bar. Session **names** are never
changed — `proj`, auto-join, and tmux-resurrect all key off them.

### 1. Setting a label

- `prefix T` → tmux `command-prompt -I "#{@claude_task}" -p "task label:"`,
  pre-filled with the current label for easy editing.
- Stores the text in the session option `@claude_task`.
- Empty input clears the label (empty string is falsy in tmux `#{?…}`
  conditionals, so all displays drop it automatically).

### 2. Display surfaces

Label shown only when set:

| Surface | Change |
|---|---|
| Ghostty tab / Dock / ⌘-Tab | `set-titles-string` → `#{?@claude_attn,🔔 ,}#S#{?#{@claude_task}, · #{@claude_task},}` |
| tmux status-left | ` #{@claude_task} ` in lavender (`#b4befe`) after the session name |
| proj picker (both fzf screens) | live-session lines rendered as `name  — label`; selection parsing strips everything from `  — ` on |

### 3. Hash color for the session name

New helper `bin/tmux-session-color.sh <session_name>`:

- `cksum` of the name → index into ~8 Catppuccin Mocha accent colors
  (blue, mauve, green, peach, teal, pink, yellow, sapphire — no red, which
  reads as an error state).
- Prints `#[fg=<color>,bold] <name> ` for embedding in status-left,
  replacing the current hardcoded blue.
- Same name → same color across restarts; tmux status bar only (Ghostty
  tab titles and the Dock are text-only).

## Files touched

- `.tmux.conf` — `bind T`, `set-titles-string`, `status-left`
- `bin/tmux-session-color.sh` — new
- `config/zsh/04-aliases.zsh` — picker list rendering + selection parsing

## Out of scope

- Persisting labels across tmux server restarts (tmux-resurrect may or may
  not carry user options; follow-up if wanted).
- Automatic labeling (Claude-generated titles or Haiku summaries) —
  explicitly rejected; labels are manual only.
- Color in Ghostty tab bar / Dock (text-only surfaces).
