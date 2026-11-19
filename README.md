# dotfiles

Terminal configuration with fast shell startup (~98ms), modular zsh config,
modern CLI tools, and a project-workspace workflow built on **Ghostty + tmux +
yazi** with Claude Code integration.

## Quick Start

This repo is a **user layer** on the
[subaud starter](https://github.com/subaud-tools/starter), set up with
**[kempt](https://kempt.tools)**. The starter is the base: tmux, Ghostty and
yazi, every subaud suite tool with its release setup, the shared rules and
process skills, and the adoptable `pi` and `neovim` packages. This layer adds
only what is its own (see [`kempt.toml`](kempt.toml)); what the starter
carries is changed there, never copied here.

**1. Set up the machine from the starter, then add this layer:**
```bash
curl -fsSL https://kempt.tools/install.sh | sh
kempt init -profile suite https://github.com/subaud-tools/starter.git
kempt adopt pi && kempt adopt neovim
git clone https://github.com/schuettc/dotfiles.git <checkout>
kempt layer add dotfiles <checkout> -profile developer
```
`kempt layer add` shows the combined plan (base and layer) and applies it on
your confirmation. Packages here are namespaced `dotfiles/<pkg>`; profiles are
`developer` (everything on a Mac), `workspace` (a Linux workspace) and
`minimal` (just the shell).

Family tools bring their own hooks, plugins, agent channels, services and
skills through the starter: kempt fetches each tool's setup with its binary
and shows both in the plan before anything is applied.

**2. Open Ghostty, then:**
```bash
proj               # pick a project → spawns a workspace (shell + yazi)
```

See [`docs/terminal-usage.md`](docs/terminal-usage.md) for the day-to-day
cheat sheet, and [`docs/setup-notes.md`](docs/setup-notes.md) for the full
design rationale behind the migration off cmux.

### Day-to-day

| What you want | Command |
|---|---|
| See what would change (nothing runs) | `kempt plan` |
| Apply the manifest / converge this machine | `kempt apply` |
| Pull latest + self-update + converge | `kempt update` (aliased `dotup`) |
| Prompt-safe status line (used by `proj`) | `kempt status` |
| Add / drop a package from this machine's selection | `kempt adopt <pkg>` / `kempt drop <pkg>` |

Every kempt run is idempotent and shows its plan first. `developer` selects
`core`, `terminal`, `markedit`, `claude`, `swiftbar`,
`family-skills` (the .tools family build, release and onboarding skills),
`pi-personal` (pi extensions and settings on top of the starter's pi: yolo
mode, pi-hail, pi-casebook, the default model) and `pi-channels` (muster in
pi); `minimal` selects `core`. Three packages are opt-in only:
`session-themes`, the local llama.cpp inference rig `pi-llama` (it needs
GGUF weights this repo doesn't ship), and `etr-capture` (yt-dlp, whisper.cpp
and ffmpeg for bettor-help's ETR capture, on the machine that runs it).

**Follow-ups** only you can do, for what you selected (kempt prints package
notes after `apply`): `kempt login` for diazo and hail; pair your phone with
hail; sign in to Claude Code on first run; `sift init --root
DIR`; SwiftBar's plugin folder, login item and Accessibility grant;
`casebook init` (and, if you want it, `casebook hooks install`) and `cull
init` per project; with `pi-llama`, the model weights; with `etr-capture`,
the whisper.cpp model. Restart any
running pi session so it picks up new extensions.

## What's Included

### Terminal stack: Ghostty + tmux + yazi

- **[Ghostty](https://ghostty.org)** — native, GPU-accelerated terminal
  emulator, configured by the starter. `config/ghostty/config.mac` adds the
  MonoLisaCode font on top, from Ghostty's macOS config path, which loads
  after the starter's.
- **tmux**: multiplexer providing splits and detach/reattach (reboot
  recovery is `proj`'s saved tab). Config in `.tmux.conf`.
- **[yazi](https://yazi-rs.github.io)** — TUI file explorer that lives in a
  right-side pane. Config in `config/yazi/` (with a MarkEdit opener for
  Markdown), linked to `~/.config/yazi-user` beside the starter's and chosen
  by `YAZI_CONFIG_HOME`.
- **neovim** ([LazyVim](https://lazyvim.org)) — terminal editor and system-wide
  `$EDITOR`, from the starter's `neovim` package.

### The workspace workflow

One **project workspace = one Ghostty window**. `proj` is a two-screen
picker: Screen 1 picks a project (or jumps to a live session); Screen 2
picks a session — or names new work. **The session name is the identity**:
sessions are born `<project>/<work>` (home base: bare `<project>`), every
surface aligns to that name — Claude included, which is launched with
`--name <session>` — and renames go through one gesture (`prefix T`,
where you type only the work half) so no surface is left behind.
Isolation is the agent's job —
proj opens everything in the primary clone and coding agents make their
own worktrees when they need them.

Shell helpers (in `config/zsh/04-aliases.zsh`; flags come before the
positional project — `proj --claude dotfiles` works, `proj dotfiles
--claude` silently drops the flag):

| Command | What it does |
|---------|--------------|
| `proj` | two-screen picker → jump to a session, open the home base, or name new work |
| `proj <project>` | skip Screen 1 |
| `proj --claude` | same, but auto-launch `claude` in the left pane |
| `proj --cursor` | same, but auto-launch Cursor Agent in the left pane |
| `proj --add` / `--remove` | add or delete an entry in `~/.config/proj/roots` |
| `pt <work>` / `pt <project> <work>` | create-or-attach `<project>/<work>` without the picker |
| `tat <name>` | attach-or-create a named session |
| `proj-clean` | reap idle sessions (shell/yazi only — no Claude/editor/server) |

⌘T in a project window auto-joins a new tmux session for that project (via
proj's shell wrapper, fired by `config/zsh/06-proj.zsh`); ⌘N opens a fresh window at `$HOME`, outside
any project. Project roots are configured per-machine in `~/.config/proj/roots`
(not tracked; first `proj` run sets it up). See
[`docs/terminal-usage.md`](docs/terminal-usage.md) for the day-to-day walkthrough.

### Shell Configuration
- **Modular zsh** — configs split into numbered files in `config/zsh/`
- **Lazy-loaded NVM** — Node available immediately, NVM loads on demand
- **Starship prompt** — two-line prompt with git status, language versions, AWS profile

### Pi

pi itself, its base extensions, the worker and reviewer subagents and the
process skills come from the starter's `pi` and `way-of-working` packages.
`pi-personal` adds the user's own extensions (pi-provider-guard, pi-typesafe-ai, pi-hail, pi-casebook), the default model,
yolo mode with pi-hail answering prompts, and the encrypted MCP token store;
kempt folds its package list into the starter's.

Local models are the separate, opt-in `pi-llama` package: a launchd-managed
llama.cpp router on the loopback-only port 42137, for a machine that has the
GGUF weights. See [`docs/pi-local-models.md`](docs/pi-local-models.md).

### Modern CLI Tools (the core package)
| Tool | Replaces | Purpose |
|------|----------|---------|
| eza | ls | File listing with icons and git status |
| bat | cat | Syntax-highlighted file viewing |
| ripgrep | grep | Fast search |
| fd | find | Fast file finding |
| zoxide | cd | Smart directory jumping |
| fzf | — | Fuzzy finder |
| delta | diff | Syntax-highlighted git diffs |
| atuin | history | Shell history with sync |

### tmux status bar

The status bar surfaces, for the focused pane:

- **right** — current git branch + dirty count, the Claude context-window %
  (`⌬ 49%`, green/yellow/red) when the focused pane is running Claude, and
  the date/time.

The branch/context indicators come from the helpers in `bin/`.

### Claude Code Integration

The `claude` package installs [Claude Code](https://claude.ai/code) (the `claude-code` cask) and configures:

- **Status line** (`config/claude/statusline.sh`) — model + working directory.
  (Context % and git status are shown in the **tmux** status bar instead, to
  avoid duplication.)
- **Attention bell** (`config/claude/claude-notify.sh`) — the `Notification`
  and `Stop` hooks ring the tmux bell for the exact Claude pane, which drives
  a 🔔 on the Ghostty tab. Purely
  in-terminal — no macOS notification, no Dock bounce.

### Cursor Agent

This repo does not select Cursor. If you use the
[Cursor Agent CLI](https://cursor.com/cli) yourself, `muster setup --force
--agent cursor` wires it onto the muster bus and `proj --cursor` launches it. See
[`docs/cursor-bridge.md`](docs/cursor-bridge.md).

### muster — cross-terminal agent bus

**[muster](https://github.com/schuettc/muster)**
is a local coordination bus that lets standing agent sessions in
separate terminals (Claude Code, Codex and pi) message and hand tasks to each
other — no copy/paste, subscription-only. The `muster` package installs the
checksummed binary from muster.tools to `~/.local/bin/muster`, and its release
setup adds the Claude Code plugin and session hooks, and the Codex hooks and
MCP server. No service is installed: `muster serve` starts when the first agent
needs it, or from proj, and serves a page listing the agents. This
repo adds the pi side: the MCP server in `~/.config/mcp/mcp.json` and, with
`pi-channels`, the mail channel. Don't want muster? Leave it out of your
selection (the install-wizard skill walks through each package).

- **In an agent session:** the agent calls `register_agent` once, then
  `send_message` / `task_create` / `task_claim` / `get_inbox` / … to coordinate
  with peers. A tmux "wake" knocks the recipient's pane so idle agents notice.
- **From any shell:** `muster agents`, `muster inbox <alias>`, `muster tasks <alias>`,
  `muster send <alias> "…" --from me` to observe and drive the bus.
- **From tmux:** `prefix @` copies the session's bus alias to the clipboard;
  `prefix m` nudges the session's agent to drain its inbox now (idle agents
  otherwise only check mail at turn boundaries).

Verify with `claude mcp list` (`muster … ✔ Connected`). Full docs live in the
muster repo's README.

### The naming contract (tmux ↔ muster)

The tmux session name (`#S`) is the identity (spec:
`docs/superpowers/specs/2026-08-08-proj-session-identity-design.md`). A
session is born named for its work (`<project>/<work>`, via the proj
picker or `pt`), and every surface aligns to that one name: tab titles,
the picker, Claude's own conversation name, and — when muster is
installed — the bus alias, which its SessionStart hook seeds from the
session name.

Claude gets that name at launch, via `claude --name <session>`. Both
launch paths carry it: `proj --claude` / `pt --claude` type it into the
pane (`__claude_launch_cmd`), and a hand-typed bare `claude` picks up
`#S` through the wrapper in `04-aliases.zsh`. Nothing is injected and
nothing waits for the agent to boot. `--name` writes a transcript
custom-title record, which is what `config/claude/statusline.sh` reads to
decide a name is user-set — so the first status tick already sees Claude
and `#S` aligned.

Renames go through one gesture so no surface is left behind. **You type
the work, never the project.** `prefix T` runs
`bin/tmux-session-rename.sh --prompt`, which pre-fills the prompt with
the work segment alone (a home-base session, whose `#S` is a bare
`<project>`, starts empty); the rename half re-attaches the project
prefix to whatever comes back. A typed name that already contains a `/`
is taken verbatim — the escape hatch for re-homing a session under
another project. From there it validates the name (letters, digits, `-`,
`_`, `/`), refuses names any live session holds, renames the tmux
session, and — with muster — calls `muster become`, which claims the
alias on the bus (mail follows via lineage) and types `/rename` into the
registered Claude pane.

`/rename` inside Claude flows the other way: the statusline proves the
name is user-set via the transcript custom-title record, then renames the
tmux session (plus `muster become --no-inject` when available — the name
already came from `/rename`). Note the asymmetry: that path takes the
name literally and does **not** re-attach a project prefix, so
`/rename foo` on `dotfiles/nfl-4` leaves a bare `foo`. Use `prefix T`.
Without muster, both gestures still work, just tmux-only.

`@claude_task` survives as a display-only subtitle — whatever Claude
currently calls the conversation (usually its auto topic), rendered in
the title's middle segment and deduped against the session name. It
never renames anything. `@claude_task_promoted` records the last title
the statusline acted on, so a stale transcript title (a swallowed
`/rename`) can't revert an operator's rename. `@claude_task_manual` is
retired.

## Structure

```
<checkout>/
├── .zshrc                 # Minimal loader, sources config/zsh/*
├── .tmux.conf             # tmux config (prefix C-a, plugins, status bar)
├── kempt.toml             # declarative machine manifest (kempt reads this)
├── bin/
│   ├── tmux-git-status.sh      # branch + dirty count for status-right
│   ├── tmux-claude-context.sh  # Claude context % for status-right
│   ├── tmux-session-color.sh   # stable name-hashed session color
│   └── claude-attn             # raise/clear the Claude attention flag
├── config/
│   ├── ghostty/config.mac # Ghostty font on top of the starter's config
│   ├── yazi/              # File-explorer config (Catppuccin Mocha, MarkEdit)
│   ├── pi/skills/         # the .tools family skills (family-skills)
│   ├── zsh/
│   │   ├── 00-terminal.zsh      # OSC 7 cwd reporting (Ghostty new-tab dir)
│   │   ├── 01-paths.zsh        # PATH + EDITOR (nvim) + YAZI_CONFIG_HOME
│   │   ├── 02-nvm-lazy.zsh     # Lazy NVM loading
│   │   ├── 03-tools.zsh        # Atuin, zoxide, fzf init
│   │   ├── 03-proj-roots.zsh   # project-roots loader (proj/pt)
│   │   ├── 04-aliases.zsh      # aliases + proj/pt/tat/proj-clean
│   │   ├── 05-completions.zsh  # Shell completions
│   │   └── 06-proj.zsh         # ⌘T → fires proj's auto-join once PATH is set
│   ├── starship.toml      # Prompt configuration
│   ├── atuin/config.toml  # History sync settings
│   └── claude/
│       ├── statusline.sh      # Claude Code status line (model + dir)
│       └── claude-notify.sh   # Notification/Stop hooks → tmux bell
└── docs/
    ├── pi-local-models.md # Pi + local llama.cpp models
    ├── terminal-usage.md  # day-to-day cheat sheet
    ├── terminal-setup.md  # install tutorial
    ├── cursor-bridge.md   # Cursor Agent + muster workflow
    └── setup-notes.md     # design rationale / running log
```

## Customization

| To change… | Edit |
|------------|------|
| Aliases / workspace commands | `config/zsh/04-aliases.zsh` |
| Project root directories | `proj --add` / `--remove` / `--edit` (writes `~/.config/proj/roots`) |
| The prompt | `config/starship.toml` ([starship.rs/config](https://starship.rs/config/)) |
| Terminal font | `config/ghostty/config.mac` (the rest of Ghostty's config is the starter's) |
| tmux behavior / status bar | `.tmux.conf` |
| Homebrew packages | the package's `install` step in `kempt.toml`, then `kempt apply` |

## Requirements

- macOS
- [Homebrew](https://brew.sh)
- MonoLisa font (paid; not installed by any package) — without it Ghostty falls back to a
  default monospace. Install your `.ttf`s into `~/Library/Fonts/` first. The
  config expects MonoLisa **3.000+**, whose family is `MonoLisaCode` (v2.x
  shipped as `MonoLisa`); on 3.000 the variable `MonoLisaCodeUpright.ttf` covers
  every weight.
