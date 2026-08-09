# dotfiles update nudge — design

**Date:** 2026-08-08
**Status:** approved

## Problem

Updating is already one command (`dotup` → pull + re-run install.sh), but
nothing tells you *when* to run it. A machine drifts behind `origin/main`
silently until something visibly breaks. The pain is the trigger, not the
mechanics.

## Decision

Notify-only, surfaced at the natural session-start moment: `proj`. No
auto-apply — brew runs and tmux config reloads must never happen underneath
live sessions at arbitrary times, and a background pull conflict would fail
invisibly (silent drift, the exact failure we're killing).

## Design

### `bin/dotfiles-update-check.sh`

One script, two subcommands:

- **`status`** (default) — read `~/.cache/dotfiles-update-state`; if it
  records `behind=N` with N > 0, print exactly one dim line
  (`dotfiles: N behind · dotup`, dim per the quiet-indicator doctrine —
  idle states are dim text, no emoji). Otherwise print nothing. Pure file
  read: instant, no network, no git.
- **`refresh`** — if the state file is missing or older than ~4 hours:
  `git -C ~/dotfiles fetch`, then write `behind=<rev-list --count
  HEAD..origin/main>` to the state file. Strictly read-only against the
  working tree: fetch only, never pull, never touch checked-out files.
  Network failure leaves the old state file in place (fail quiet).

State file format is `key=value` lines so future consumers (tmux status
segment, SwiftBar, launchd fetcher) can read it without rework.

### `proj` hook (config/zsh/04-aliases.zsh)

At proj entry: print `status`, then disown `refresh` as a background job.
Both pickers run fzf at `--height=60%`, so the printed line stays visible
above the picker. proj latency is unchanged; the signal is at most one
invocation stale — acceptable for dotfiles.

### `dotup` integration (update.sh)

After a successful update, rewrite the state file (behind=0) so the
indicator clears immediately instead of lingering until the next fetch
window.

## Error handling

- No network / fetch fails → keep prior state, print nothing extra.
- State file missing/corrupt → treat as "unknown", print nothing; next
  `refresh` rewrites it.
- `~/dotfiles` missing or not a git repo → both subcommands exit 0 silently.

## Testing

Follows the repo's existing test conventions in `tests/`: exercise
`status` output against hand-written state files (behind, current,
missing, corrupt), and `refresh`'s age-gate logic. Fetch itself is not
unit-tested (network).

## Out of scope (deliberate)

- Background timers/launchd, tmux status-line or SwiftBar surfaces — the
  state file is designed so these bolt on later; separate brainstorm.
- Any Go rewrite of install/update machinery — separate brainstorm
  ("the bigger change"); Go has no job in a 20-line trigger.
- Auto-applying updates.
