# Neovim adoption — design

**Date:** 2026-07-08
**Status:** Approved

## Goal

Adopt neovim (via the LazyVim distribution) as the canonical editor for the
terminal stack, replacing VS Code as `$EDITOR`. Everything terminal-born —
yazi opens, `git commit`, `crontab`, `proj --edit` — lands in neovim inside
the existing Ghostty + tmux workflow instead of bouncing out to a GUI app.

VS Code **stays in the Brewfile** and on disk; it just stops being what the
dotfiles point at. Nothing in the repo references it as `$EDITOR` anymore.

## Context

- The stack is already TUI-centric: Ghostty + tmux + yazi + lazygit +
  Claude Code. The editor was the one remaining GUI hop.
- The user is new to modal editing, so the config must deliver IDE-grade
  behavior out of the box rather than requiring vim fluency to assemble.
- First-class language support required: TypeScript/JavaScript, Python, Go.

## Decision

Use the **LazyVim starter** structure: a small (~6 file) config that pulls
in LazyVim as a plugin, not a fork of the distro. LazyVim was chosen over
kickstart.nvim and a handwritten config because it is itself an opinionated
single solution — VS Code parity (file tree, fuzzy find, LSP, git signs,
lazygit integration) with zero assembly, letting the learning budget go to
modal editing instead of plugin plumbing.

## Components

### 1. Brewfile

- Add `brew "neovim"`.
- Keep `cask "visual-studio-code"` (user decision) — update its trailing
  comment since it is no longer "$EDITOR for yazi + git commit".

### 2. `config/nvim/` (new, tracked)

LazyVim starter layout:

```
config/nvim/
├── init.lua                  # bootstraps lua/config/lazy.lua
├── lazy-lock.json            # committed — pins every plugin version
├── lua/
│   ├── config/
│   │   ├── lazy.lua          # lazy.nvim bootstrap + LazyVim import
│   │   ├── options.lua       # editor options
│   │   ├── keymaps.lua       # custom keymaps (start empty)
│   │   └── autocmds.lua      # custom autocmds (start empty)
│   └── plugins/
│       └── theme.lua         # catppuccin (mocha) — matches Ghostty
└── lazyvim.json              # enabled extras
```

- **Colorscheme:** Catppuccin Mocha, matching Ghostty and tmux.
- **Extras:** `lang.typescript`, `lang.python`, `lang.go`. Mason
  auto-installs the language servers (vtsls, pyright + ruff, gopls) on
  first run.
- **`lazy-lock.json` is committed** so a fresh machine reproduces the
  exact plugin set (lockfile philosophy).

### 3. `install.sh`

Symlink the config with the same pattern as yazi/zsh:

```sh
ln -sfn "$DOTFILES_DIR/config/nvim" "$CONFIG_DIR/nvim"
```

with a `backup_if_exists` guard, consistent with neighboring blocks.

### 4. Cutover in `config/zsh/01-paths.zsh`

```sh
export EDITOR='nvim'
export VISUAL='nvim'
```

No `--wait` needed — terminal editors block naturally; the comment block
explaining the `--wait` dance is replaced by a simpler one. yazi,
`git commit`, `crontab`, and `proj --edit` all follow `$EDITOR`
automatically; no other config changes required.

### 5. Docs

- README: add neovim to the terminal-stack section; stop describing VS
  Code as `$EDITOR`.
- `docs/terminal-usage.md`: mention nvim where editor behavior comes up,
  if it does.

## Testing

1. `brew install neovim` (via `brew bundle`), run `install.sh` symlink step.
2. Headless bootstrap: `nvim --headless "+Lazy! sync" +qa` — installs all
   plugins and language servers non-interactively.
3. `:checkhealth` — review for errors (warnings acceptable where benign).
4. Open a real TypeScript file and a Python file; confirm the LSP attaches
   (diagnostics/hover present).
5. End-to-end: `git commit` opens nvim; save-quit completes the commit.
6. yazi: open a file, confirm it lands in nvim.

## Out of scope

- Uninstalling VS Code (stays installed and in the Brewfile).
- Custom keymaps/plugins beyond the theme — start with stock LazyVim
  opinions; customize only after real usage reveals needs.
- tmux ↔ nvim pane-navigation integration (vim-tmux-navigator) — revisit
  after the basics are muscle memory.

## Learning ramp (not a repo change)

`:Tutor` for the 30-minute interactive vim lesson; LazyVim's which-key
shows every binding on `Space`, making the config discoverable without
memorization.
