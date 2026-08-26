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

## Choose an installation path

| Installation | Use when | Command |
|---|---|---|
| Standard | You want the normal terminal and coding-agent setup | `./install.sh` |
| Guided selective | You want to review and approve packages individually | Open `claude` in the repo and ask for the install wizard |
| Explicit selective | You already know which packages you want | `./packages/run.sh <package>…` |
| Local Pi models | You want the opt-in Pi + llama.cpp stack | `./packages/run.sh pi` after a standard install, or `./packages/run.sh core pi` when `core` is not installed (Homebrew required) |

The local Pi model stack is intentionally excluded from the standard install.
Installing the Pi app by itself is also supported with
`npm install -g @earendil-works/pi-coding-agent`; that does not install or
configure llama.cpp. See [`pi-local-models.md`](pi-local-models.md) for the full
set of local-model choices.

The standard package set is `core`, `terminal`, `nvim`, `markedit`, `claude`,
`swiftbar`, `codex`, `cursor`, and `muster`; `pi` is available only when it is
explicitly selected.

## Standard one-command install

```bash
git clone git@github.com:schuettc/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

`install.sh` is idempotent — safe to re-run. It installs the standard package
set and will:

1. Install Homebrew (if missing) and apply the selected packages' Brewfiles:
   Ghostty, tmux, yazi, neovim, fzf, fd, ripgrep, bat, eza, zoxide, atuin,
   starship, gh, jq, VS Code, Nerd Font casks, …
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

## If the install fails partway

`install.sh` is **resilient and re-runnable** — it no longer aborts on the first
error. A failed step (a flaky brew cask, no network for TPM, …) prints a `⚠`
warning and the install keeps going; a summary of all warnings prints at the end.
Fix what's listed and just run `./install.sh` again (it's idempotent). Only a
truly fatal problem — no Homebrew — stops it.

## Uninstall / reset

```bash
./uninstall.sh           # remove our symlinks + config, restore *.bak backups
./uninstall.sh --purge   # the above, plus uninstall SwiftBar + delete TPM
```

`uninstall.sh` undoes what `install.sh` did, conservatively:

- Removes **only** symlinks that point into this dotfiles dir, then restores any
  `*.bak` backup the install made — it never deletes a real file it didn't
  create, and leaves foreign symlinks alone.
- Removes the `~/.local/bin/claude-attn` symlink and the SwiftBar Login Item +
  plugin-dir preference.
- Strips the hooks / statusline / permission it merged into
  `~/.claude/settings.json` (backed up to `settings.json.bak` first), preserving
  any of your own entries.
- Leaves Homebrew packages and the SwiftBar **app** installed unless you pass
  `--purge`.

It does **not** kill your tmux server (you'd lose live sessions) — restart tmux
or run `tmux source ~/.tmux.conf` afterward to apply the reverted config.

**Reset** = uninstall then reinstall: `./uninstall.sh && ./install.sh`.

## Post-install (manual, one-time)

A few things can't be fully automated:

| Step | Why / how |
|------|-----------|
| **MonoLisa font** | Paid font, not in the Brewfile. Drop your `.ttf`s into `~/Library/Fonts/` or Ghostty falls back to a default monospace. Needs **3.000+** — its family is `MonoLisaCode` (v2.x was `MonoLisa`), and the variable `MonoLisaCodeUpright.ttf` supplies every weight. |
| **Atuin sync** | `atuin login` (existing account) or `atuin register` (new) for cross-machine shell history. |
| **GitHub CLI** | `gh auth login` |
| **VS Code** | Sign in for Settings Sync if you want your extensions. (kept as a GUI editor; `$EDITOR` is nvim.) |
| **neovim** | First `nvim` launch bootstraps lazy.nvim + restores the pinned plugins from `lazy-lock.json` + Mason installs language servers (needs network, takes a couple of minutes). On machines whose global pip config points at a private mirror, Mason's `ruff` install may need `PIP_INDEX_URL=https://pypi.org/simple nvim`; if `sum.golang.org` DNS fails, `gopls` may need `GOSUMDB=off`. |
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
project:~/dotfiles
```

Each line is one of two kinds:

| Line | Meaning |
| --- | --- |
| `~/GitHub/schuettc` | A **root** — its immediate children are projects. |
| `project:~/dotfiles` | A **project** — this directory itself is the project. |

Use `project:` for a repo that lives directly in `$HOME` and so has no root
to sit under. Do not list bare `~` as a root to reach it: that makes every
folder in your home directory a project, and opening a shell in `~/Downloads`
then gets ambushed by the `proj` picker instead of giving you a shell.

`project:` also fits a directory whose children are data rather than code —
list `~/bettor-help` as a root and every dated slate directory inside it
becomes a separate project in the picker.

The bottom of the `proj` picker carries `[+ add new project root…]` and
`[- remove a project root…]`; either one edits the file and drops you back
into a rebuilt list, so you can fix your roots and pick a project in one
trip. The same two are available directly as flags.

Edit the file with `proj --add` and `proj --remove` (Tab multi-selects) —
both rewrite it for you. `proj --edit` opens it in `$EDITOR` for anything
those two can't express.

### 2. Open your first workspace

```bash
proj                 # two-screen fzf picker
```

`proj` is a two-screen picker: **Screen 1** picks a project (or jumps to a
live session); **Screen 2** picks a session — jump to a live one, open the
**home base** (`🏠 <project> — home base`), or name new
work (`+ new work…`), which creates `<project>/<work>`. Either way you land
in a tmux session with a shell on the left (~70%) and yazi on the right
(~30%), and that Ghostty window becomes the "workspace." See
[`terminal-usage.md`](terminal-usage.md) for the full walkthrough.

To auto-launch Claude in the left pane instead of an empty shell:

```bash
proj --claude
```

### 3. Add more terminals to the workspace

Inside a project's Ghostty window, press **⌘T**. The new tab inherits the
project cwd (`tab-inherit-working-directory = true` in `config/ghostty/config`)
and the zsh auto-join hook opens `proj <project>` — Screen 2 — so you pick a
live session, the home base, or name new work; naming a tab is always an
explicit gesture. Each tab is an independent tmux session — run `claude` (or
anything) in whichever you like.

By contrast, **⌘N (new window)** opens fresh at `$HOME`
(`window-inherit-working-directory = false`, `working-directory = home`) —
*outside* any project. Run `proj` there to enter or create a workspace.

If ⌘T ever lands at `$HOME` instead of the project (e.g., OSC 7 didn't
propagate), use the manual fallback: `pt <work>` (from inside the project
dir) or `pt <project> <work>`.

## Verifying it works

Run through this checklist:

1. `proj` → pick a project → **two panes** appear (shell + yazi), tmux status
   bar at the top showing the session name.
2. `Ctrl-A` then `f` → the yazi pane **toggles off**; press again → back.
3. `Ctrl-A` then `d` → **detach**; `tmux ls` lists the session; `tmux attach`
   → back where you were.
4. ⌘T inside the window → a new tab opens the Screen-2 picker; name new work
   there and `tmux ls` shows both sessions.
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
| `proj` | Two-screen picker → jump to a session, open the home base, or name new work |
| `proj --claude` | Same, but auto-launch claude in the left pane |
| `proj --edit` | Edit `~/.config/proj/roots` |
| `pt <work>` / `pt <project> <work>` | Create-or-attach `<project>/<work>` without the picker |
| `pt --claude <work>` | Same, with claude |
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
- **A new shell drops into the `proj` picker instead of a shell** — a root in
  `~/.config/proj/roots` is too broad, so an ordinary directory looks like a
  project. Usually a bare `~` line: it makes `~/Downloads`, `~/Library` and
  friends into projects. Replace it with `project:` lines for the specific
  repos you meant (`proj --edit`).
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
