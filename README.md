# dotfiles

Terminal configuration with fast shell startup (~98ms), modular zsh config,
modern CLI tools, and a project-workspace workflow built on **Ghostty + tmux +
yazi** with Claude Code integration.

## Quick Start

**1. Clone and install:**
```bash
git clone https://github.com/schuettc/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
```

**2. Set up shell history sync (optional):**
```bash
atuin login        # or: atuin register
```

**3. Open Ghostty, then:**
```bash
proj               # pick a project → spawns a workspace (shell + yazi)
```

See [`docs/terminal-usage.md`](docs/terminal-usage.md) for the day-to-day
cheat sheet, and [`docs/setup-notes.md`](docs/setup-notes.md) for the full
design rationale behind the migration off cmux.

## What's Included

### Terminal stack: Ghostty + tmux + yazi

- **[Ghostty](https://ghostty.org)** — native, GPU-accelerated terminal
  emulator. Config in `config/ghostty/config` (MonoLisaCode font, Catppuccin
  Mocha, keybinds, image-paste workaround, Ctrl+Enter newline).
- **tmux** — multiplexer providing session persistence (via
  tmux-resurrect + tmux-continuum), splits, and detach/reattach. Config in
  `.tmux.conf`.
- **[yazi](https://yazi-rs.github.io)** — TUI file explorer that lives in a
  right-side pane. Config in `config/yazi/`.

### The workspace workflow

One **project workspace = one Ghostty window**. `proj` is a two-screen,
worktree-aware picker: Screen 1 picks a project (or jumps to a live session);
Screen 2 picks what to work on, and **the branch decides isolation** — the
default branch opens the project's primary clone (home base, for reading /
coordinating), any other branch transparently opens a git worktree at
`<repo>/.worktrees/<branch>` so parallel work never collides in one tree. Each
tab in a window attaches to its own tmux session (`<project>`, `<project>-2`, …
for the primary clone; `<project>/<branch>` for a worktree) with a shell + yazi
layout. Shell helpers (in `config/zsh/04-aliases.zsh`):

| Command | What it does |
|---------|--------------|
| `proj` | two-screen picker → enter/create a workspace; choose home base or a branch (own worktree) |
| `proj --claude` | same, but auto-launch `claude` in the left pane |
| `pt [name]` | spawn another terminal in a project (next `name-N` session) |
| `tat <name>` | attach-or-create a named session |
| `proj-clean` | reap idle sessions (shell/yazi only — no Claude/editor/server) |
| `bell-clear` | dismiss the attention banner (`-k` to kill flagged sessions) |

⌘T in a project window auto-joins a new tmux session for that project (via
`config/zsh/06-tmux-autojoin.zsh`); ⌘N opens a fresh window at `$HOME`, outside
any project. Project roots are configured per-machine in `~/.config/proj/roots`
(not tracked; first `proj` run sets it up). The full worktree workflow — the
Screen-2 rows, `.worktreeinclude`, pruning, and the `⚠ primary` status-bar cue
— is in [`docs/terminal-usage.md`](docs/terminal-usage.md).

### Shell Configuration
- **Modular zsh** — configs split into numbered files in `config/zsh/`
- **Lazy-loaded NVM** — Node available immediately, NVM loads on demand
- **Starship prompt** — two-line prompt with git status, language versions, AWS profile

### Modern CLI Tools (via Brewfile)
| Tool | Replaces | Purpose |
|------|----------|---------|
| eza | ls | File listing with icons and git status |
| bat | cat | Syntax-highlighted file viewing |
| ripgrep | grep | Fast search |
| fd | find | Fast file finding |
| zoxide | cd | Smart directory jumping |
| fzf | — | Fuzzy finder |
| delta | diff | Syntax-highlighted git diffs |
| lazygit | — | Git TUI |
| atuin | history | Shell history with sync |

### tmux status bar

The status bar surfaces, for the focused pane:

- **left** — an attention banner (`⚠ N: session1, session2`) listing any
  session whose Claude finished a turn / is waiting for input and that you
  haven't visited yet. Clears when you switch to the session.
- **right** — current git branch + dirty count, a peach `⚠ primary` badge
  when the focused pane is in a project's primary clone while linked worktrees
  exist (the cue to go work in a worktree), the Claude context-window %
  (`⌬ 49%`, green/yellow/red) when the focused pane is running Claude, and
  the date/time.

The branch/context indicators come from the helpers in `bin/`.

### Claude Code Integration

The install script configures [Claude Code](https://claude.ai/code) with:

- **Status line** (`config/claude/statusline.sh`) — model + working directory.
  (Context % and git status are shown in the **tmux** status bar instead, to
  avoid duplication.)
- **Attention bell** (`config/claude/claude-notify.sh`) — the `Notification`
  and `Stop` hooks ring the tmux bell for the exact Claude pane, which drives
  the status-left attention banner and a 🔔 on the Ghostty tab. Purely
  in-terminal — no macOS notification, no Dock bounce.

## Structure

```
~/dotfiles/
├── .zshrc                 # Minimal loader, sources config/zsh/*
├── .tmux.conf             # tmux config (prefix C-a, plugins, status bar)
├── Brewfile               # Homebrew packages and casks
├── install.sh             # One-command setup
├── bin/
│   ├── tmux-git-status.sh      # branch + dirty count for status-right
│   ├── tmux-claude-context.sh  # Claude context % for status-right
│   └── tmux-attention.sh       # attention banner for status-left
├── config/
│   ├── ghostty/config     # Terminal config (fonts, theme, keybinds)
│   ├── yazi/              # File-explorer config (Catppuccin Mocha)
│   ├── zsh/
│   │   ├── 01-paths.zsh        # PATH + EDITOR (code --wait)
│   │   ├── 02-nvm-lazy.zsh     # Lazy NVM loading
│   │   ├── 03-tools.zsh        # Atuin, zoxide, fzf init
│   │   ├── 03-proj-roots.zsh   # project-roots loader (proj/pt)
│   │   ├── 04-aliases.zsh      # aliases + proj/pt/tat/proj-clean/bell-clear
│   │   ├── 05-completions.zsh  # Shell completions
│   │   └── 06-tmux-autojoin.zsh # ⌘T → auto-join project tmux session
│   ├── starship.toml      # Prompt configuration
│   ├── atuin/config.toml  # History sync settings
│   └── claude/
│       ├── statusline.sh      # Claude Code status line (model + dir)
│       └── claude-notify.sh   # Notification/Stop hooks → tmux bell
└── docs/
    ├── terminal-usage.md  # day-to-day cheat sheet
    ├── terminal-setup.md  # install tutorial
    └── setup-notes.md     # design rationale / running log
```

## Customization

| To change… | Edit |
|------------|------|
| Aliases / workspace commands | `config/zsh/04-aliases.zsh` |
| Project root directories | `proj --edit` (writes `~/.config/proj/roots`) |
| The prompt | `config/starship.toml` ([starship.rs/config](https://starship.rs/config/)) |
| Terminal settings / keybinds | `config/ghostty/config` |
| tmux behavior / status bar | `.tmux.conf` |
| Homebrew packages | `Brewfile`, then `brew bundle` |

## Requirements

- macOS
- [Homebrew](https://brew.sh)
- MonoLisa font (paid; not in Brewfile) — without it Ghostty falls back to a
  default monospace. Install your `.ttf`s into `~/Library/Fonts/` first. The
  config expects MonoLisa **3.000+**, whose family is `MonoLisaCode` (v2.x
  shipped as `MonoLisa`); on 3.000 the variable `MonoLisaCodeUpright.ttf` covers
  every weight.
