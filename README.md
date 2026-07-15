# dotfiles

Terminal configuration with fast shell startup (~98ms), modular zsh config,
modern CLI tools, and a project-workspace workflow built on **Ghostty + tmux +
yazi** with Claude Code integration.

## Quick Start

**1. Clone and install:**
```bash
git clone https://github.com/schuettc/dotfiles.git ~/dotfiles && cd ~/dotfiles && ./install.sh
```

**2. Open Ghostty, then:**
```bash
proj               # pick a project → spawns a workspace (shell + yazi)
```

See [`docs/terminal-usage.md`](docs/terminal-usage.md) for the day-to-day
cheat sheet, and [`docs/setup-notes.md`](docs/setup-notes.md) for the full
design rationale behind the migration off cmux.

### Selective install

Don't want everything `install.sh` installs? Clone the repo, open `claude`
in it, and ask it to run the install wizard — it walks you through each
package (what it is, what it touches), lets you pick a subset, and installs
only those.

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
- **neovim** ([LazyVim](https://lazyvim.org)) — terminal editor and system-wide
  `$EDITOR`. Config in `config/nvim/` (Catppuccin Mocha; TypeScript, Python,
  and Go language servers via Mason).

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

### Modern CLI Tools (via packages/*/Brewfile)
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

### Codex (GPT) bridge

Claude Code stays the primary harness, with [OpenAI Codex](https://github.com/openai/codex)
(`cask "codex"`) wired in two complementary ways so you get GPT for a second
opinion without leaving Claude Code:

- **MCP bridge** — `install.sh` registers Codex as a user-scope MCP server
  (`claude mcp add codex -s user -- codex mcp-server`), so Claude Code can
  delegate a discrete coding task or ask GPT for a second opinion mid-session
  via the `codex` MCP tool. Verify with `claude mcp list` (look for
  `codex … ✔ Connected`).
- **Standalone** — `codex` in its own tab for an independent pass; run both
  agents on the same tricky task and let agreement/divergence guide you.

Both run on a **ChatGPT subscription** (`codex login` — browser OAuth), not a
metered OpenAI API key. Check auth with `codex login status`. See
[`docs/codex-bridge.md`](docs/codex-bridge.md) for the day-to-day workflow.

### muster — cross-terminal agent bus

Where the Codex bridge is *vertical* (one terminal), **[muster](https://github.com/schuettc/muster)**
is *horizontal*: a local coordination bus that lets standing agent sessions in
separate terminals (Claude Code and/or Codex) message and hand tasks to each
other — no copy/paste, subscription-only. The `muster` package self-installs
the whole stack when Go is present: clones the repo (now public — HTTPS, no
SSH auth needed) to `~/GitHub/schuettc/muster` if missing, builds
`~/.local/bin/muster`, installs a **LaunchAgent** (`tools.muster.serve` —
`muster serve` runs at login, restarts on crash, logs to
`~/.local/share/muster/serve.log`), and registers the MCP server in both Claude
Code and Codex (`claude mcp add muster -s user -- muster mcp`,
`codex mcp add muster -- muster mcp`). Session hooks (auto-register on the bus +
self-resolving inbox via `muster hook`, built into the binary since v0.3.0) are
merged into the Claude/Codex settings by the same script. Don't want muster? Skip it and pick
the rest of the packages with the install-wizard skill (see "Selective
install" below).

- **In an agent session:** the agent calls `register_agent` once, then
  `send_message` / `task_create` / `task_claim` / `get_inbox` / … to coordinate
  with peers. A tmux "wake" knocks the recipient's pane so idle agents notice.
- **From any shell:** `muster agents`, `muster inbox <alias>`, `muster tasks <alias>`,
  `muster send <alias> "…" --from me` to observe and drive the bus.

Verify with `claude mcp list` (`muster … ✔ Connected`). Full docs live in the
muster repo's README.

## Structure

```
~/dotfiles/
├── .zshrc                 # Minimal loader, sources config/zsh/*
├── .tmux.conf             # tmux config (prefix C-a, plugins, status bar)
├── install.sh             # One-command setup — runs every package below
├── packages/
│   ├── lib.sh             # Shared install helpers (run_pkg, warn/die, backups)
│   ├── run.sh             # Runs an explicit package list (the wizard's entry point)
│   └── <name>/pkg.sh      # Per-package install/verify + its own Brewfile
│       # core terminal nvim markedit claude swiftbar codex muster
├── bin/
│   ├── tmux-git-status.sh      # branch + dirty count for status-right
│   ├── tmux-claude-context.sh  # Claude context % for status-right
│   ├── tmux-attention.sh       # attention banner for status-left
│   ├── tmux-session-color.sh   # stable name-hashed session color
│   └── claude-attn             # raise/clear the Claude attention flag
├── config/
│   ├── ghostty/config     # Terminal config (fonts, theme, keybinds)
│   ├── yazi/              # File-explorer config (Catppuccin Mocha)
│   ├── nvim/              # neovim config (LazyVim, Catppuccin Mocha)
│   ├── zsh/
│   │   ├── 00-terminal.zsh      # OSC 7 cwd reporting (Ghostty new-tab dir)
│   │   ├── 01-paths.zsh        # PATH + EDITOR (nvim)
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
    ├── codex-bridge.md    # Claude Code + Codex (GPT) workflow
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
| Homebrew packages | `packages/<name>/Brewfile`, then `brew bundle --file=packages/<name>/Brewfile` |

## Requirements

- macOS
- [Homebrew](https://brew.sh)
- MonoLisa font (paid; not in any package's Brewfile) — without it Ghostty falls back to a
  default monospace. Install your `.ttf`s into `~/Library/Fonts/` first. The
  config expects MonoLisa **3.000+**, whose family is `MonoLisaCode` (v2.x
  shipped as `MonoLisa`); on 3.000 the variable `MonoLisaCodeUpright.ttf` covers
  every weight.
