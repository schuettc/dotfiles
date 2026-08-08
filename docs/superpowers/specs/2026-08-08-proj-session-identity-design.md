# proj → session-identity realignment (design)

**Date:** 2026-08-08
**Status:** approved by operator (dotfiles-2 session)
**Companion:** muster-side changes get their own spec/plan in the muster repo (§5);
coordination runs over the bus to `durable-alias`.

## 1. Problem

proj was designed branch/worktree-first: Screen 2 organizes a project by its
branches, creates `<project>/<branch>` worktree sessions, and treats "new
session" as an anonymous numbered slot (`<project>-2`, `-3`, …). Actual
practice moved to session-identity-first, and the live data proves it:

- Zero live `project/branch` sessions exist; the flow Screen 2 is built
  around is unused.
- Nearly every live session is an anonymous slot in the primary clone with
  the real identity bolted on as a `@claude_task` label ("nfl-3",
  "code-review", "hosted muster").
- When worktree sessions were wanted, they were made by hand and named for
  the work (`ci-cd`, `musterA`), bypassing proj's naming.
- The rest of the stack is already session-identity-first: scratch keys pads
  to the harness session, muster v0.9.0's `become` gives sessions durable
  meaningful aliases with lineage-following mail, and tmux titles lead with
  the alias.

The `@claude_task` / `@claude_task_manual` naming contract (2026-08-05)
exists largely to compensate for meaningless session names. Give sessions
meaningful names at birth and the two-layer machinery collapses.

## 2. Naming model

**The tmux session name is the identity.** One name, chosen when work
starts, aligned everywhere.

- Project sessions are named **`<project>/<work>`** (e.g. `dotfiles/proj-picker`,
  `bettor-help-workspace/nfl-3`). The operator types only `<work>`; proj
  prepends the project. Sessions stay on the per-project server
  (`proj-<project>`) as today.
- The home base (primary clone, read/coordinate) stays bare **`<project>`**.
- Sessions outside any project (default server, `tat`) stay unprefixed —
  absence of a prefix means "not project work".
- `<work>` charset: letters, digits, `-`, `_`. No `.`, `:`, whitespace
  (tmux target separators); `/` is reserved for the project prefix. The
  picker rejects anything else.
- Muster alignment is automatic: its SessionStart hook seeds alias =
  session name, so a session born `dotfiles/proj-picker` is addressable as
  that alias with no new wiring. Project-qualified names make bus-global
  alias collisions structurally impossible across projects.
- scratch is unaffected (pads key on the harness session id, not the name).
- **Retired:** numbered slots (`<project>-N`), `@claude_task_manual`, and
  all label-promotion machinery. `@claude_task` survives as a
  **display-only subtitle**: Claude's auto-generated topic, rendered in the
  title's middle segment, never touching the session name.

## 3. Picker and session creation

**Screen 1** (unchanged shape): live sessions first, listed identity-first
(`project/work · topic`), then project directories, then the roots-file
editors.

**Screen 2** shrinks to three kinds of rows:

- `●` live sessions of this project (name · topic subtitle)
- `🏠` home base — bare `<project>` session in the primary clone
- `+ new work…` — prompt for `<work>`, then create-or-attach
  `<project>/<work>` in the primary clone directory with the standard
  layout. `--claude` / `--cursor` behave as today.

**Deleted:** all worktree machinery — branch rows, `+ new branch…`,
`+ prune worktrees…`, `__proj_ensure_worktree`, `__proj_worktree_list`,
`__proj_prune_worktrees`, `__proj_copy_includes` / `.worktreeinclude`
handling, and `__proj_launch_numbered`. Isolation is the agent's job
(EnterWorktree / the worktree-isolation doctrine); hand-made worktrees are
managed with git directly. Existing `.worktrees/` trees are untouched.

**pt** becomes `pt [--claude|--cursor] [<project>] <work>` — project
auto-detected from cwd when omitted; a work name is required (no slot
grabbing).

**Auto-join** (⌘T in a project dir) stops minting `<project>-N` sessions.
It opens proj's Screen 2 for that project instead — naming is always an
explicit gesture.

`proj-clean` is unchanged.

## 4. Rename: one gesture, all surfaces

A session has one name at a time; the only way to change it is the gesture
that changes every surface. Nothing may half-rename.

- **`prefix T`** is the rename gesture (shim script, successor of
  `tmux-muster-label.sh`):
  - muster present → delegate to muster's `become`-based rename command:
    claims the alias (mail follows via lineage), renames the tmux session,
    injects `/rename <name>` into the registered live Claude pane.
    Feedback via `display-message`.
  - muster absent → plain `tmux rename-session`. No send-keys (doctrine:
    typing into panes is muster's job); Claude's internal name catches up
    on the operator's next `/rename`.
- **Statusline promotion** re-targets: when the transcript custom-title
  equals `session_name` (proof the name is user-set via `/rename`), the
  statusline renames the tmux session — via `become --no-inject` when
  muster is present (the name already came from `/rename`; re-typing would
  loop), plain `rename-session` otherwise. The fast path (name already
  aligned → no transcript read) is preserved.
- **Auto topics** only ever write the `@claude_task` subtitle. No code path
  renames a session from an auto topic — the never-demote rule, re-anchored
  on `#S`.
- **Collisions:** renaming onto a name a live session already holds must
  not steal identity. Muster's hook grows if-absent/suffix semantics (its
  filed follow-up from bus thread 154); the muster-less fallback refuses
  the rename if the target session name exists on any proj server.

## 5. Muster changes (coordinated, not blocking)

The dotfiles half works with plain tmux on day one — that is the
independence guarantee (dotfiles ⊥ muster). Muster upgrades the same
gestures:

1. An operator-facing `become`-style rename command the prefix-T shim can
   call: alias claim + tmux session rename + `/rename` injection.
2. A `--no-inject` variant for the statusline promotion path.
3. The rename-collision guard in its SessionStart/seed path (already
   filed).
4. Deprecate `muster label` as the human-handle concept; the subtitle is
   written only by the statusline.
5. Verify the alias charset accepts `/` (old `project/branch` session
   names were seeded before, so this is expected to hold — confirm).

The contract's neutral meeting point moves from the `@claude_task` option
pair to the tmux session name (`#S`) — pure tmux, no muster required.

## 6. Migration

Nothing forced. Live numbered sessions keep working — the picker lists
whatever exists; rename them with the new gesture as you touch them, or let
them wind down. README's naming-contract section is rewritten to the
`#S`-anchored contract. Existing tests for the retired machinery
(`tmux-muster-label`, `statusline-name-sync`, `proj-picker`) are rewritten
against the new behavior, same throwaway-tmux-server conventions.

## 7. Testing

Standalone `tests/*.test.zsh` files per repo convention (real throwaway
tmux server, `ok()` PASS/FAIL):

- picker: Screen-2 list building (live rows, home base, new-work row; no
  worktree rows), name validation, create-or-attach naming.
- rename shim: muster-absent renames the session and nothing else;
  muster-present delegates with recorded args; collision refusal.
- statusline: custom-title promotion renames the session (both modes);
  auto topic writes only the subtitle; never-demote; aligned fast path
  reads no transcript.
- pt / auto-join: named creation, no slot minting.

Manual smoke: create a named session via the picker; `prefix T` rename with
muster live (alias follows, inbox intact); `/rename` from inside Claude
promotes; PATH-stripped muster-less run of both gestures.

## Out of scope

- Any replacement worktree management in proj — deleted, not relocated.
- Muster's hosted backend / cross-machine concerns.
- Retroactive renaming of existing sessions.
