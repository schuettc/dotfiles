# scratch ↔ tmux integration — design

**Date:** 2026-07-13
**Status:** Design approved, ready for implementation plan
**Repo:** dotfiles (companion to the `scratch` tool at `~/GitHub/schuettc/scratch`)

## Summary

Integrate the `scratch` per-worktree markdown scratchpad into the existing
Ghostty + tmux + yazi workspace. Every workspace's right column becomes a fixed
vertical stack — **scratch (notes) → yazi (files) → terminal (shell)** — built
by a single shared helper, toggled as a unit by `prefix f`, and installed via
`install.sh`. This is the companion change the `scratch` design doc
(`~/GitHub/schuettc/scratch/docs/superpowers/specs/2026-07-13-scratch-notepad-design.md`)
scoped as a follow-on.

## Current state (what exists today)

- **Right side = one full-height pane running `yazi`**, 30% wide. There is no
  vertical split. yazi is the *default* occupant but the pane is used for other
  things ad hoc.
- **Three sites create that pane** with the same
  `split-window -h -l 30% … yazi` + "keep yazi focused during its terminal
  probe, then refocus the left pane after ~0.5s" logic:
  1. `config/zsh/04-aliases.zsh` → `__proj_launch` (the `proj` entry point).
     `__proj_launch_numbered` reuses it.
  2. `config/zsh/04-aliases.zsh` → the `pt` function's pane-build block.
  3. `config/zsh/06-tmux-autojoin.zsh` → `__auto_join_project` (the `⌘T`
     autojoin path that spawns `<project>-N` sessions).
- **Per-project tmux servers**: each project uses socket `proj-<name>`
  (`__proj_srv`). All pane creation runs on `-L "$srv"`.
- **`prefix f`** (`.tmux.conf`) toggles a single yazi pane, keyed off
  `window_panes > 1` — too coarse once the column holds multiple panes.
- **Agent-pin** (`.tmux.conf`): `@agent_pin` (default 1); `after-split-window`
  and `after-resize-pane` hooks re-pin `{top-left}` to `-x 70%` whenever
  `window_panes >= 3`. Paired with yazi's `-l 30%`. `prefix P` toggles the pin.

## Goals

- A `scratch` notes pane present in every workspace, top of the right column.
- A general shell at the bottom of the right column for quick commands.
- One canonical definition of the right column (no more triplicated pane logic).
- `prefix f` toggles the whole column as a unit, robust to whatever is running
  in any pane.
- Reproducible install via `install.sh`.

## Non-goals (YAGNI)

- No change to the `scratch` binary itself (separate repo/spec).
- No change to how Claude Code's `--tmux` agent-teams spawn subagent panes —
  they may append below the terminal, which is acceptable.
- No separate per-pane toggles (scratch-only / yazi-only). `prefix f` acts on
  the whole column.
- No change to the 30% column width or the 70% agent-pin (both reused as-is).

## Layout

Every workspace: main pane (left, 70%) + a **30%-wide right column**, a fixed
three-pane vertical stack:

| Position | Pane | Size |
|----------|------|------|
| top | `scratch` (notes) | ~12 rows, fixed |
| middle | `yazi` (files) | fills the remainder |
| bottom | plain shell (terminal) | ~10 rows, fixed |

- Baseline is now **4 panes** (main + 3). The existing agent-pin (`>= 3` →
  `{top-left} -x 70%`) therefore fires at baseline and holds main at 70% /
  column at 30% — **unchanged**; no retuning of the pin or the 30% width.
- Claude's subagent panes append **below** the terminal as spawned. This is
  accepted (the "terminal always at the very bottom" invariant is explicitly
  not required).

## Components

### 1. `__proj_right_column` helper (new; `config/zsh/04-aliases.zsh`)

Signature: `__proj_right_column <srv> <session> <dir>`

Builds the right column for an already-created session whose only pane is the
main/left pane. Responsibilities:

1. Split the main pane horizontally into a **30%** right pane; the top-right
   pane runs `scratch`.
2. Split the scratch pane vertically → `yazi` in the middle.
3. Split the yazi pane vertically → a **plain shell** at the bottom, sized to
   ~10 rows; size scratch's slice to ~12 rows.
4. **Tag** each of the three panes with a pane user option `@sidebar 1` so the
   toggle can identify the column by what we built, not by what runs in it.
5. **Startup probe dance**: both `scratch` and `yazi` query the terminal on
   startup (background-color / cursor-position); tmux delivers the terminal's
   responses to the *focused* pane, so each must be focused while it probes or
   the responses leak into another pane as escape-code garbage (and `scratch`
   can hang waiting). The helper focuses scratch while it probes, then yazi
   while it probes, then returns focus to the main pane — extending the current
   single-yazi refocus (a detached, timed job so it never blocks the
   `attach`/`switch-client` that follows).

All three current pane-creation sites call this one helper instead of their
inline `split-window … yazi` blocks:
- `__proj_launch` (04-aliases.zsh)
- the `pt` function block (04-aliases.zsh)
- `__auto_join_project` (06-tmux-autojoin.zsh)

Exact pane targeting uses pane ids (`%NN`) as the current code does (the
`=name` exact-match form is a session target, invalid for split/select).

### 2. `prefix f` rework (`.tmux.conf`)

Toggle the whole column by the `@sidebar` tag:

- If any pane in the window carries `@sidebar 1` → kill all such panes (back to
  just the main pane, plus any non-sidebar panes like agent panes, untouched).
- Else → rebuild the column via `__proj_right_column` for the current session.

Because identification is by tag, agent panes and "other things running in the
column" never confuse the toggle. Rebuilding re-launches `scratch`, which reads
`$PWD/.scratch.md` fresh from disk (the file is the source of truth), so no
in-pane state is lost.

### 3. Global gitignore (`~/.config/git/ignore`)

Add `.scratch.md`. This is git's XDG-default global excludes path (honored even
though `core.excludesfile` is unset), so the scratchpad never pollutes any repo.
A user who wants to commit notes in a specific repo can un-ignore it there.

### 4. Install (`install.sh`)

Add a `scratch` build step mirroring the existing `muster` block: when
`~/GitHub/schuettc/scratch` is cloned and Go is present, build the binary into
`~/.local/bin` (idempotent; skip cleanly if repo/tools absent). Remove the
duplicate `~/go/bin/scratch` left by the earlier `go install` so there is one
canonical binary in `~/.local/bin` (the `~/go/bin` PATH entry in
`config/zsh/01-paths.zsh` stays — generally useful for other Go tools).

## Per-session scoping

The scratch pane runs in the session's working dir, so:
- **Worktree sessions** (`proj/branch`) each get their own `.scratch.md`.
- **Numbered sessions** (`proj-2`, `proj-3`) on the same project root **share**
  one `.scratch.md`. This is fine and intended: `scratch`'s autosave +
  fsnotify reload / dirty-flag machinery reconciles concurrent edits across
  panes — exactly what it was built for.

## Error handling / edge cases

- If `scratch` is not on `PATH`, the scratch pane's `scratch` command fails and
  its pane shows the shell error, but the rest of the column and the workspace
  still come up. (Install step ensures it's present on configured machines.)
- The `@sidebar` toggle rebuild targets the current session's dir; if the
  column helper is called when a column already exists, `prefix f`'s
  tag-detection path tears it down first, so rebuild is only reached when none
  exists.
- Probe dance timing reuses the current ~0.5s budget per probing app; on a slow
  start a probe response could still race, same risk profile as today's yazi.

## Testing / verification

tmux config and zsh launch paths are not unit-testable; verify by driving the
real workspace on a throwaway project:

1. **`proj`** into a test project → assert 4-pane layout (main 70%; right column
   30% = scratch top ~12 rows, yazi middle, terminal bottom ~10 rows), focus
   lands on **main** with no escape-code garbage in any pane, and
   `.scratch.md` is created in the session dir after typing + autosave.
2. **`pt <name>`** → same layout via that path.
3. **`⌘T` autojoin** (`<project>-N`) → same layout via `06-tmux-autojoin.zsh`.
4. **`prefix f`** → tears the whole column down to just main; again → rebuilds
   scratch → yazi → terminal; focus returns to main.
5. **Subagent spawn** (Claude `--tmux`) → new pane appends below the terminal,
   `{top-left}` stays pinned at 70%.
6. **`tmux source-file ~/.tmux.conf`** (prefix r) parses with no errors.
7. **Global ignore** → `git check-ignore .scratch.md` inside a repo returns a
   match.
8. **Install** → on a clean run with the repo cloned + Go present,
   `~/.local/bin/scratch` is built and `command -v scratch` resolves; no
   `~/go/bin/scratch` remains.

## Rollout / sequencing

1. Add `__proj_right_column`; convert the three sites to call it.
2. Rework `prefix f`; verify toggle + layout on a live workspace.
3. Add `.scratch.md` to `~/.config/git/ignore`.
4. Add the `scratch` build step to `install.sh`; remove the `~/go/bin` copy.
