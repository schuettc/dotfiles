# Terminal Setup

A step-by-step guide to setting up the **Ghostty + tmux + yazi** terminal
workflow on a fresh macOS machine. This is the install tutorial; for the
day-to-day cheat sheet see [`terminal-usage.md`](terminal-usage.md), and for
the design rationale see [`setup-notes.md`](setup-notes.md).

## What you'll end up with

- **Ghostty** — native, GPU-accelerated terminal (replaced cmux, which leaked
  CALayers and hammered WindowServer over long uptimes)
- **tmux** — session persistence, splits, detach/reattach, restore-on-reboot
- **yazi** — a file-explorer pane on the right of each workspace
- **A workspace workflow** — one Ghostty window per project; each tab is its
  own tmux session; `proj`/`pt` to spawn them; auto-join on ⌘T
- **Claude Code integration** — a cross-session attention indicator (🔔 in the
  tab/Dock title + a SwiftBar menu-bar badge when Claude is waiting on you) and a
  tmux status bar showing git status and Claude's context %

## Prerequisites

- macOS (Apple Silicon or Intel)
- [Homebrew](https://brew.sh) — `install.sh` installs it if missing
- A GitHub SSH key (to clone the repo via `git@`)

## One-command install

```bash
git clone git@github.com:schuettc/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

`install.sh` is idempotent — safe to re-run. It will:

1. Install Homebrew (if missing) and run `brew bundle` to install everything
   in the `Brewfile`: Ghostty, tmux, yazi, fzf, fd, ripgrep, bat, eza,
   zoxide, atuin, starship, gh, jq, VS Code, Nerd Font casks, …
2. Symlink configs into place (backing up any existing file to `*.bak`):
   - `~/.zshrc`, `~/.tmux.conf`
   - `~/.config/zsh/`, `~/.config/ghostty/`, `~/.config/yazi/`,
     `~/.config/starship.toml`, `~/.config/atuin/`, `~/.config/claude/`
3. Clone TPM (tmux plugin manager) to `~/.tmux/plugins/tpm` and headlessly
   install the tmux plugins (tmux-sensible, tmux-resurrect, tmux-continuum)
4. Merge Claude Code settings into `~/.claude/settings.json` — wires the
   `Notification` and `Stop` hooks to `claude-notify.sh` and sets the
   status line

Then reload your shell:

```bash
source ~/.zshrc      # or just open a fresh Ghostty window
```

## Post-install (manual, one-time)

A few things can't be fully automated:

| Step | Why / how |
|------|-----------|
| **MonoLisa font** | Paid font, not in the Brewfile. Drop your `.ttf`s into `~/Library/Fonts/` or Ghostty falls back to a default monospace. |
| **Atuin sync** | `atuin login` (existing account) or `atuin register` (new) for cross-machine shell history. |
| **GitHub CLI** | `gh auth login` |
| **VS Code** | Sign in for Settings Sync if you want your extensions. (`code` is the `$EDITOR` used by yazi + git commit.) |
| **Claude Code** | First `claude` launch prompts to sign in. |
| **SwiftBar Accessibility** | One-time, can't be automated (macOS TCC is SIP-protected). The menu-bar 🔔's **click-to-focus** (un-minimize + raise the waiting session's window) needs it: System Settings → Privacy & Security → **Accessibility** → enable **SwiftBar**, then quit + reopen it. The 🔔 badge and titles work *without* this — only click-to-bring-forward needs it. |
| **1Password** | Sign in to the app + CLI if you use it. |

## First run

### 1. Configure your project roots

The `proj` workflow needs to know which directories contain your projects.
This is **per-machine** (not tracked in git, since paths differ between
machines). The first time you run `proj`, it prompts you to set this up:

```bash
proj
```

You'll get an interactive picker of common candidates that exist on disk
(plus an option to enter a custom path). Your selection is written to
`~/.config/proj/roots` — one absolute path per line. You can edit it any
time with:

```bash
proj --edit
```

A typical `~/.config/proj/roots`:

```
~/GitHub/schuettc
~/learning-with-court
```

### 2. Open your first workspace

```bash
proj                 # two-screen fzf picker
```

`proj` is a two-screen picker: **Screen 1** picks a project (or jumps to a
live session); **Screen 2** (git repos only) picks what to work on — the
**home base** (`🏠 primary clone — on <branch>`) or a branch, which opens in
its own git worktree. Picking a non-default branch transparently creates a
worktree at `<repo>/.worktrees/<branch>`. Either way you land in a tmux
session with a shell on the left (~70%) and yazi on the right (~30%), and that
Ghostty window becomes the "workspace." See
[`terminal-usage.md`](terminal-usage.md) for the full worktree workflow.

To auto-launch Claude in the left pane instead of an empty shell:

```bash
proj --claude
```

### 3. Add more terminals to the workspace

Inside a project's Ghostty window, press **⌘T**. The new tab inherits the
project cwd (`tab-inherit-working-directory = true` in `config/ghostty/config`)
and the zsh auto-join hook detects the project and spawns the next session
(`<project>-2`, `-3`, …) with the same shell+yazi layout. Each tab is an
independent tmux session — run `claude` (or anything) in whichever you like.

By contrast, **⌘N (new window)** opens fresh at `$HOME`
(`window-inherit-working-directory = false`, `working-directory = home`) —
*outside* any project. Run `proj` there to enter or create a workspace.

If ⌘T ever lands at `$HOME` instead of the project (e.g., OSC 7 didn't
propagate), use the manual fallback: `pt` (from inside the project dir) or
`pt <project>`.

## Verifying it works

Run through this checklist:

1. `proj` → pick a project → **two panes** appear (shell + yazi), tmux status
   bar at the top showing the session name.
2. `Ctrl-A` then `f` → the yazi pane **toggles off**; press again → back.
3. `Ctrl-A` then `d` → **detach**; `tmux ls` lists the session; `tmux attach`
   → back where you were.
4. ⌘T inside the window → a new tab auto-joins `<project>-2`; `tmux ls` shows
   both.
5. Start `claude` in a pane, send a prompt, switch away. When Claude **waits for
   your input** (the Notification hook), the session's tab/Dock title gets a 🔔
   and the SwiftBar menu-bar bell turns red with a count — click it in the
   dropdown to bring that window forward. The flag clears when you switch to the
   session. (Turn-end still rings the in-terminal bell + `⚠ 1: <project>`.)
6. Status-right shows the git branch + dirty count, and `⌬ NN%` when the
   focused pane is running Claude.
7. **Persistence:** `tmux kill-server`, then `tmux attach` → tmux-continuum
   restores your sessions and layouts.

## Day-to-day commands

| Command | What it does |
|---------|--------------|
| `proj` | Pick / spawn a project workspace (shell + yazi) |
| `proj --claude` | Same, but auto-launch claude in the left pane |
| `proj --edit` | Edit `~/.config/proj/roots` |
| `pt [name]` | Spawn another terminal in a project (`<name>-N`) |
| `pt --claude [name]` | Same, with claude |
| `tat <name>` | Attach-or-create a named session |
| `proj-clean` | Reap idle sessions (shell/yazi only) — `-n` for dry run |
| `bell-clear` | Dismiss the attention banner — `-k` to kill flagged sessions |
| `claude-attn raise` | Flag the current session for attention (🔔 + menu-bar badge); `clear` / `list` / `focus <s>` round it out. Any script/hook/skill can call it. |

Key bindings (prefix is `Ctrl-A`): `prefix f` toggle yazi, `prefix d` detach,
`prefix s` session picker, `prefix h/j/k/l` move between panes,
`prefix H/L` resize, `prefix z` zoom. `Ctrl+Enter` / `Shift+Enter` insert a
newline in Claude without submitting. Full reference in
[`terminal-usage.md`](terminal-usage.md).

## Troubleshooting

- **`proj` says "No project roots configured"** — run `proj` interactively to
  set them up, or `proj --edit`. (The roots file is `~/.config/proj/roots`,
  per-machine, untracked.)
- **⌘T lands at `$HOME`, not the project** — tmux didn't forward the cwd via
  OSC 7. Reload tmux (`Ctrl-A r`) or `tmux kill-server` + `tmux attach`; then
  use `pt` for the current tab.
- **tmux config changes not taking effect** — `Ctrl-A r` to reload, or
  `tmux kill-server` (detach first) for a clean restart. continuum restores
  your sessions.
- **tmux plugins didn't install** — the bootstrap needs a fresh server:
  `tmux kill-server; tmux new-session -d; ~/.tmux/plugins/tpm/bin/install_plugins; tmux kill-server`.
- **Ghostty config changes not applying** — `⌘⇧,` to reload, or quit and
  relaunch Ghostty (some settings need a full restart).
- **`⌘V` won't paste images into Claude** — use `Ctrl+V`. Known Ghostty
  limitation (discussion #10099).
- **Claude alerts silent** — only sessions started *after* the hooks were
  configured fire them; restart a long-running session to pick them up.
