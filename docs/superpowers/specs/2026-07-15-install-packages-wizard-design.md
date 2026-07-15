# Install Packages + Wizard — Design

**Date:** 2026-07-15
**Status:** approved (graph + package contract confirmed by Court)

## Goal

Two co-equal install paths over one set of per-package scripts:

1. `./install.sh` — unchanged experience: one command installs everything, in
   dependency order. For people (including Court) who want the whole setup.
2. **Install wizard** — a repo-level Claude Code skill for strangers who cloned
   the public repo: walks through each package (what it is, how it works, what
   it touches), lets them pick a subset, resolves dependencies, runs the chosen
   package scripts individually, verifies each.

Both paths execute the same `packages/<name>/pkg.sh` scripts, so they cannot
drift.

## Package graph

Hard deps only where things actually break without them:

| package  | contents                                                              | deps     |
|----------|-----------------------------------------------------------------------|----------|
| core     | brew bootstrap, CLI formulas (eza/bat/rg/fd/zoxide/fzf/delta/lazygit/atuin/jq/gh/…), zsh configs, starship, atuin import | —        |
| terminal | Ghostty cask+config, tmux + .tmux.conf + TPM bootstrap, yazi, tmux helper bins (tmux-*.sh, proj-right-column.sh), scratch (go install) | core     |
| nvim     | neovim formula + LazyVim config                                        | core     |
| markedit | MarkEdit editor styles (skips cleanly if app absent)                   | core     |
| claude   | statusline, notify hook, settings merge, claude-attn CLI               | core     |
| swiftbar | SwiftBar cask, menu-bar bell plugin, login item, A11y note             | claude   |
| codex    | Codex cask + login reminder; MCP bridge into Claude (conditional)      | core     |
| muster   | clone (HTTPS)/build/LaunchAgent daemon/MCP + session hooks             | terminal |

Design decisions embedded in the graph:

- **claude works without terminal** — statusline.sh has a non-tmux branch and
  claude-notify.sh no-ops without tmux (both verified in code). The wizard
  states the degradation: statusline only, no bells.
- **muster requires terminal** — the tmux wake/badge is its operator surface.
- **Integrations are conditional steps inside packages, not graph edges:**
  - codex → registers the Claude MCP bridge iff `claude` binary exists
    (always true under the wizard, which runs inside Claude Code).
  - muster → merges Claude session hooks (SessionStart/Stop) iff claude binary
    exists; registers in Codex iff codex binary exists.
  - Each conditional step reports whether it ran or was skipped.
- **muster session hooks move from the claude settings section into the muster
  package.** Skipping muster means no muster hooks — today's install.sh writes
  them unconditionally in the Claude section, which is wrong under selective
  install.
- **Config files ship whole with their owning package** (e.g. all zsh modules
  ship with core even though `proj` drives terminal tools) — config text is
  inert without the tools; packages gate tools, services, and integrations,
  not lines of config.

## Package contract

```
packages/
  lib.sh              # shared: warn/die/backup_if_exists, WARNINGS array, DOTFILES_DIR
  core/pkg.sh         # + Brewfile
  terminal/pkg.sh     # + Brewfile
  nvim/pkg.sh         # + Brewfile
  markedit/pkg.sh
  claude/pkg.sh
  swiftbar/pkg.sh     # + Brewfile
  codex/pkg.sh        # + Brewfile
  muster/pkg.sh       # + Brewfile
```

Each `pkg.sh` defines exactly:

- `PKG_DESC` — one-line description (the wizard's inventory source)
- `PKG_DEPS=(…)` — hard deps from the table above
- `pkg_install()` — idempotent; body lifted from today's install.sh section;
  runs `brew bundle --file="$PKG_DIR/Brewfile"` first when a Brewfile exists
- `pkg_verify()` — cheap post-check (binary on PATH, symlink correct, service
  running, MCP `✔ Connected`); prints PASS/FAIL lines, returns nonzero on FAIL

Rules: scripts are bash-3.2-safe (macOS stock bash), no `set -e` (matches the
resilient-by-design install philosophy), every step warns-and-continues except
genuinely fatal ones.

The root monolithic `Brewfile` is **retired**; its entries are distributed to
package Brewfiles (formula placement follows the package that needs the tool;
general CLI QoL tools live in core). Full install = union of all package
Brewfiles = today's set.

## Root install.sh

Keeps: macOS guard, Homebrew bootstrap (fatal if missing), warning summary,
"Next steps" epilogue. Replaces the body with running every package in fixed
dependency order:

```
core terminal nvim markedit claude swiftbar codex muster
```

Static order, no topo-sort machinery (8 packages, fixed graph — YAGNI). For
each package: source pkg.sh in a subshell-safe way, run `pkg_install`, then
`pkg_verify`, collecting warnings.

muster clone URL changes to HTTPS (`https://github.com/schuettc/muster.git`) —
the repo is public now; strangers need no SSH auth.

## The wizard — `.claude/skills/install-wizard/SKILL.md`

Repo-level skill: available to anyone who opens Claude Code in their clone.
The SKILL.md instructs Claude to:

1. **Inventory** — read every `packages/*/pkg.sh` for PKG_DESC/PKG_DEPS (the
   skill hardcodes nothing; packages are the source of truth).
2. **Prerequisite scan** — macOS check; report what's already present (brew,
   go, claude, codex, SwiftBar, an existing ~/.claude/settings.json that will
   be merged not overwritten).
3. **Walk packages one at a time** — for each: what it is, how it works, what
   it touches (casks installed, files symlinked, settings merged, login items
   and LaunchAgents created — persistence called out explicitly), then ask
   install yes/no. One question per message.
4. **Resolve the dep closure** — expand picks with their deps, tell the user
   exactly what got added and why, confirm the final set.
5. **Execute** — run each chosen package script individually (in dependency
   order), streaming output; on failure, warn and ask continue/stop.
6. **Verify + report** — run `pkg_verify` per package; end with an honest
   summary (installed / skipped / failed / manual steps like SwiftBar
   Accessibility and `codex login`).

The wizard never edits package scripts and never installs anything not in the
confirmed set.

## Migration & verification

Pure reshuffle: each `pkg_install` body is lifted from the current working
install.sh sections (which were battle-verified this week). Verification on
this machine:

1. Snapshot observable state (symlink targets, `claude mcp list`, LaunchAgent
   state, settings.json hooks, brew leaves).
2. Run the new root `./install.sh` end-to-end (idempotent by design).
3. Diff state — expect no changes.
4. Run `pkg_verify` for all packages — expect all PASS.
5. Exercise the wizard flow for a small subset in conversation to validate the
   skill instructions read correctly.

README updates: Structure section reflects `packages/`, muster section notes
HTTPS clone, new "Selective install" subsection pointing at the wizard skill,
Brewfile references updated.

## Out of scope

- Linux/Windows support (macOS guard stays).
- Uninstall/rollback per package.
- Version pinning of brew packages.
- General topo-sort / package-manager machinery beyond the fixed 8.
